#define _POSIX_C_SOURCE 200809L
#define R_NO_REMAP
#include <R.h>
#include <R_ext/Utils.h>
#include <Rinternals.h>

#if !defined(__EMSCRIPTEN__)
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

typedef struct {
    SEXP commands;
    SEXP arguments;
    SEXP input_path;
    SEXP output_path;
    SEXP error_path;
    size_t stage_count;
    size_t pipe_count;
    int (*pipes)[2];
    pid_t *pids;
    int *active;
    int *statuses;
    int *signals;
    int input_fd;
    int output_fd;
    int error_fd;
} pipeline_context;

static void close_fd(int *fd) {
    if (*fd >= 0) {
        close(*fd);
        *fd = -1;
    }
}

static void close_pipeline_fds(pipeline_context *ctx) {
    size_t i;
    for (i = 0; i < ctx->pipe_count; ++i) {
        close_fd(&ctx->pipes[i][0]);
        close_fd(&ctx->pipes[i][1]);
    }
    close_fd(&ctx->input_fd);
    close_fd(&ctx->output_fd);
    close_fd(&ctx->error_fd);
}

static void pipeline_cleanup(void *data, Rboolean jump) {
    pipeline_context *ctx = (pipeline_context *)data;
    size_t i;
    if (jump && ctx->pids != NULL) {
        for (i = 0; i < ctx->stage_count; ++i) {
            if (ctx->active[i]) kill(ctx->pids[i], SIGTERM);
        }
        for (i = 0; i < ctx->stage_count; ++i) {
            if (ctx->active[i]) {
                while (waitpid(ctx->pids[i], NULL, 0) < 0 && errno == EINTR) {
                }
                ctx->active[i] = 0;
            }
        }
    }
    close_pipeline_fds(ctx);
    free(ctx->pipes);
    free(ctx->pids);
    free(ctx->active);
    free(ctx->statuses);
    free(ctx->signals);
    ctx->pipes = NULL;
    ctx->pids = NULL;
    ctx->active = NULL;
    ctx->statuses = NULL;
    ctx->signals = NULL;
}

static int open_path(SEXP path, int flags) {
    int fd;
    if (path == R_NilValue) return -1;
    fd = open(Rf_translateCharUTF8(STRING_ELT(path, 0)), flags, 0666);
    if (fd >= 0 && fd <= STDERR_FILENO) {
        int private_fd = fcntl(fd, F_DUPFD, STDERR_FILENO + 1);
        int saved_errno = errno;
        close(fd);
        errno = saved_errno;
        return private_fd;
    }
    return fd;
}

static void add_close_actions(posix_spawn_file_actions_t *actions, pipeline_context *ctx) {
    size_t i;
    for (i = 0; i < ctx->pipe_count; ++i) {
        posix_spawn_file_actions_addclose(actions, ctx->pipes[i][0]);
        posix_spawn_file_actions_addclose(actions, ctx->pipes[i][1]);
    }
    if (ctx->input_fd >= 0) posix_spawn_file_actions_addclose(actions, ctx->input_fd);
    if (ctx->output_fd >= 0) posix_spawn_file_actions_addclose(actions, ctx->output_fd);
    if (ctx->error_fd >= 0) posix_spawn_file_actions_addclose(actions, ctx->error_fd);
}

static char **stage_argv(pipeline_context *ctx, size_t stage) {
    SEXP args = VECTOR_ELT(ctx->arguments, (R_xlen_t)stage);
    R_xlen_t arg_count = XLENGTH(args);
    R_xlen_t i;
    char **argv = (char **)calloc((size_t)arg_count + 2, sizeof(char *));
    if (argv == NULL) Rf_error("Unable to allocate the pipeline argument vector");
    argv[0] = (char *)Rf_translateCharUTF8(STRING_ELT(ctx->commands, (R_xlen_t)stage));
    for (i = 0; i < arg_count; ++i) {
        argv[i + 1] = (char *)Rf_translateCharUTF8(STRING_ELT(args, i));
    }
    return argv;
}

static void spawn_stage(pipeline_context *ctx, size_t stage) {
    posix_spawn_file_actions_t actions;
    char **argv;
    int rc;

    rc = posix_spawn_file_actions_init(&actions);
    if (rc != 0) Rf_error("Unable to initialize process actions: %s", strerror(rc));

    if (stage > 0) {
        posix_spawn_file_actions_adddup2(&actions, ctx->pipes[stage - 1][0], STDIN_FILENO);
    } else if (ctx->input_fd >= 0) {
        posix_spawn_file_actions_adddup2(&actions, ctx->input_fd, STDIN_FILENO);
    }

    if (stage + 1 < ctx->stage_count) {
        posix_spawn_file_actions_adddup2(&actions, ctx->pipes[stage][1], STDOUT_FILENO);
    } else if (ctx->output_fd >= 0) {
        posix_spawn_file_actions_adddup2(&actions, ctx->output_fd, STDOUT_FILENO);
    }

    if (ctx->error_fd >= 0) {
        posix_spawn_file_actions_adddup2(&actions, ctx->error_fd, STDERR_FILENO);
    }
    add_close_actions(&actions, ctx);

    argv = stage_argv(ctx, stage);
    rc = posix_spawnp(&ctx->pids[stage], argv[0], &actions, NULL, argv, environ);
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    if (rc != 0) {
        Rf_error("Unable to start pipeline stage %zu: %s", stage + 1, strerror(rc));
    }
    ctx->active[stage] = 1;
}

static void record_status(pipeline_context *ctx, size_t stage, int status) {
    ctx->active[stage] = 0;
    if (WIFEXITED(status)) {
        ctx->statuses[stage] = WEXITSTATUS(status);
        ctx->signals[stage] = 0;
    } else if (WIFSIGNALED(status)) {
        ctx->signals[stage] = WTERMSIG(status);
        ctx->statuses[stage] = 128 + ctx->signals[stage];
    } else {
        ctx->statuses[stage] = 255;
        ctx->signals[stage] = 0;
    }
}

static void wait_for_pipeline(pipeline_context *ctx) {
    const struct timespec pause_time = {0, 10000000};
    size_t remaining = ctx->stage_count;
    while (remaining > 0) {
        size_t i;
        for (i = 0; i < ctx->stage_count; ++i) {
            int status;
            pid_t waited;
            if (!ctx->active[i]) continue;
            waited = waitpid(ctx->pids[i], &status, WNOHANG);
            if (waited == ctx->pids[i]) {
                record_status(ctx, i, status);
                --remaining;
            } else if (waited < 0 && errno != EINTR) {
                Rf_error("Unable to wait for pipeline stage %zu: %s", i + 1, strerror(errno));
            }
        }
        if (remaining > 0) {
            R_CheckUserInterrupt();
            nanosleep(&pause_time, NULL);
        }
    }
}

static SEXP pipeline_body(void *data) {
    pipeline_context *ctx = (pipeline_context *)data;
    size_t i;
    SEXP result;
    SEXP statuses;
    SEXP signals;
    SEXP names;

    ctx->input_fd = open_path(ctx->input_path, O_RDONLY);
    if (ctx->input_path != R_NilValue && ctx->input_fd < 0) {
        Rf_error("Unable to open pipeline input: %s", strerror(errno));
    }
    ctx->output_fd = open_path(ctx->output_path, O_WRONLY | O_CREAT | O_TRUNC);
    if (ctx->output_path != R_NilValue && ctx->output_fd < 0) {
        Rf_error("Unable to open pipeline output: %s", strerror(errno));
    }
    ctx->error_fd = open_path(ctx->error_path, O_WRONLY | O_CREAT | O_TRUNC);
    if (ctx->error_path != R_NilValue && ctx->error_fd < 0) {
        Rf_error("Unable to open pipeline error log: %s", strerror(errno));
    }

    for (i = 0; i < ctx->pipe_count; ++i) {
        if (pipe(ctx->pipes[i]) != 0) Rf_error("Unable to create pipeline pipe: %s", strerror(errno));
    }
    for (i = 0; i < ctx->stage_count; ++i) spawn_stage(ctx, i);
    close_pipeline_fds(ctx);
    wait_for_pipeline(ctx);

    PROTECT(statuses = Rf_allocVector(INTSXP, (R_xlen_t)ctx->stage_count));
    PROTECT(signals = Rf_allocVector(INTSXP, (R_xlen_t)ctx->stage_count));
    for (i = 0; i < ctx->stage_count; ++i) {
        INTEGER(statuses)[i] = ctx->statuses[i];
        INTEGER(signals)[i] = ctx->signals[i];
    }
    PROTECT(result = Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(result, 0, statuses);
    SET_VECTOR_ELT(result, 1, signals);
    PROTECT(names = Rf_allocVector(STRSXP, 2));
    SET_STRING_ELT(names, 0, Rf_mkChar("status"));
    SET_STRING_ELT(names, 1, Rf_mkChar("signal"));
    Rf_setAttrib(result, R_NamesSymbol, names);
    UNPROTECT(4);
    return result;
}
#endif

SEXP RC_exec_pipeline(SEXP commands, SEXP arguments, SEXP input_path,
                      SEXP output_path, SEXP error_path) {
#if defined(__EMSCRIPTEN__)
    Rf_error("External executable pipelines are unavailable on WebAssembly builds");
    return R_NilValue;
#else
    pipeline_context ctx;
    SEXP continuation;
    size_t stage_count;

    if (TYPEOF(commands) != STRSXP || XLENGTH(commands) == 0) {
        Rf_error("commands must be a non-empty character vector");
    }
    if (TYPEOF(arguments) != VECSXP || XLENGTH(arguments) != XLENGTH(commands)) {
        Rf_error("arguments must be a list with one element per command");
    }
    stage_count = (size_t)XLENGTH(commands);
    memset(&ctx, 0, sizeof(ctx));
    ctx.commands = commands;
    ctx.arguments = arguments;
    ctx.input_path = input_path;
    ctx.output_path = output_path;
    ctx.error_path = error_path;
    ctx.stage_count = stage_count;
    ctx.pipe_count = stage_count - 1;
    ctx.input_fd = -1;
    ctx.output_fd = -1;
    ctx.error_fd = -1;
    ctx.pipes = (int(*)[2])calloc(ctx.pipe_count, sizeof(int[2]));
    ctx.pids = (pid_t *)calloc(stage_count, sizeof(pid_t));
    ctx.active = (int *)calloc(stage_count, sizeof(int));
    ctx.statuses = (int *)calloc(stage_count, sizeof(int));
    ctx.signals = (int *)calloc(stage_count, sizeof(int));
    if ((ctx.pipe_count > 0 && ctx.pipes == NULL) || ctx.pids == NULL || ctx.active == NULL ||
        ctx.statuses == NULL || ctx.signals == NULL) {
        pipeline_cleanup(&ctx, FALSE);
        Rf_error("Unable to allocate pipeline state");
    }
    if (ctx.pipe_count > 0) {
        size_t i;
        for (i = 0; i < ctx.pipe_count; ++i) {
            ctx.pipes[i][0] = -1;
            ctx.pipes[i][1] = -1;
        }
    }

    PROTECT(continuation = R_MakeUnwindCont());
    SEXP result = R_UnwindProtect(pipeline_body, &ctx, pipeline_cleanup, &ctx, continuation);
    UNPROTECT(1);
    return result;
#endif
}
