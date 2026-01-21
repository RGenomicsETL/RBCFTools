/**
 * r_chan.c - Buffered channel implementation for R UDF
 *
 * Uses a linked-list queue internally. Senders enqueue immediately (non-blocking),
 * then wait on their own per-request condition variable for completion.
 * This avoids deadlock when the receiver (main R thread) is busy in DuckDB.
 *
 * Copyright (c) 2026 RBCFTools Authors
 * Licensed under MIT License
 */

#include "r_chan.h"

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

// =============================================================================
// Timeout Constant
// =============================================================================

static const struct timespec R_CHAN_NO_TIMEOUT_VALUE = {0, 0};
const struct timespec *R_CHAN_NO_TIMEOUT = &R_CHAN_NO_TIMEOUT_VALUE;

// =============================================================================
// Helper: Timed wait on condition variable
// =============================================================================

static int cond_timedwait(pthread_cond_t *cond, pthread_mutex_t *mtx,
                          const struct timespec *timeout) {
    if (timeout == R_CHAN_NO_WAIT) {
        return EAGAIN;  // Non-blocking - don't wait
    }
    
    if (timeout == R_CHAN_NO_TIMEOUT) {
        return pthread_cond_wait(cond, mtx);  // Wait forever
    }
    
    // Relative timeout -> absolute time
    struct timespec abs_time;
    clock_gettime(CLOCK_REALTIME, &abs_time);
    abs_time.tv_sec += timeout->tv_sec;
    abs_time.tv_nsec += timeout->tv_nsec;
    if (abs_time.tv_nsec >= 1000000000L) {
        abs_time.tv_nsec -= 1000000000L;
        abs_time.tv_sec += 1;
    }
    
    return pthread_cond_timedwait(cond, mtx, &abs_time);
}

// =============================================================================
// Channel Lifecycle
// =============================================================================

int r_chan_init_signal_pipe(r_chan_t *chan) {
    if (!chan) {
        errno = EINVAL;
        return -1;
    }
    
    if (pipe(chan->signal_pipe) != 0) {
        return -1;
    }
    
    // Make read end non-blocking
    int flags = fcntl(chan->signal_pipe[0], F_GETFL, 0);
    fcntl(chan->signal_pipe[0], F_SETFL, flags | O_NONBLOCK);
    
    // Make write end non-blocking too (don't block senders on full pipe)
    flags = fcntl(chan->signal_pipe[1], F_GETFL, 0);
    fcntl(chan->signal_pipe[1], F_SETFL, flags | O_NONBLOCK);
    
    return chan->signal_pipe[0];
}

void r_chan_cleanup(r_chan_t *chan) {
    if (!chan) return;
    
    r_chan_close(chan);
    
    // Free any remaining queue nodes
    pthread_mutex_lock(&chan->mtx);
    r_chan_node_t *node = chan->head;
    while (node) {
        r_chan_node_t *next = node->next;
        free(node);
        node = next;
    }
    chan->head = chan->tail = NULL;
    chan->len = 0;
    pthread_mutex_unlock(&chan->mtx);
    
    pthread_cond_destroy(&chan->not_empty);
    pthread_mutex_destroy(&chan->mtx);
    
    if (chan->signal_pipe[0] >= 0) {
        close(chan->signal_pipe[0]);
        chan->signal_pipe[0] = -1;
    }
    if (chan->signal_pipe[1] >= 0) {
        close(chan->signal_pipe[1]);
        chan->signal_pipe[1] = -1;
    }
}

void r_chan_close(r_chan_t *chan) {
    if (!chan) return;
    
    pthread_mutex_lock(&chan->mtx);
    
    if (!chan->is_closed) {
        chan->is_closed = true;
        
        // Wake all waiters
        pthread_cond_broadcast(&chan->not_empty);
    }
    
    pthread_mutex_unlock(&chan->mtx);
}

// =============================================================================
// Send Operation (Buffered: enqueue and return immediately)
// =============================================================================

int r_chan_send(r_chan_t *chan, void *msg, const struct timespec *timeout) {
    (void)timeout;  // Ignored for buffered channel
    
    if (!chan) {
        errno = EINVAL;
        return EINVAL;
    }
    
    // Allocate queue node
    r_chan_node_t *node = malloc(sizeof(r_chan_node_t));
    if (!node) {
        errno = ENOMEM;
        return ENOMEM;
    }
    node->msg = msg;
    node->next = NULL;
    
    pthread_mutex_lock(&chan->mtx);
    
    // Check if closed
    if (chan->is_closed) {
        pthread_mutex_unlock(&chan->mtx);
        free(node);
        errno = EPIPE;
        return EPIPE;
    }
    
    // Enqueue at tail
    if (chan->tail) {
        chan->tail->next = node;
        chan->tail = node;
    } else {
        chan->head = chan->tail = node;
    }
    chan->len++;
    
    // Signal any waiting receiver
    pthread_cond_signal(&chan->not_empty);
    
    pthread_mutex_unlock(&chan->mtx);
    
    // Signal the receiver via pipe (for R event loop)
    if (chan->signal_pipe[1] >= 0) {
        char c = 'M';
        ssize_t n = write(chan->signal_pipe[1], &c, 1);
        (void)n;  // Ignore - pipe is non-blocking
    }
    
    return 0;
}

// =============================================================================
// Receive Operation
// =============================================================================

int r_chan_recv(r_chan_t *chan, void **msg_out, const struct timespec *timeout) {
    if (!chan || !msg_out) {
        errno = EINVAL;
        return EINVAL;
    }
    
    int rv = 0;
    pthread_mutex_lock(&chan->mtx);
    
    // Wait for queue to become non-empty
    while (chan->len == 0 && !chan->is_closed) {
        if (timeout == R_CHAN_NO_WAIT) {
            pthread_mutex_unlock(&chan->mtx);
            errno = EAGAIN;
            return EAGAIN;
        }
        
        rv = cond_timedwait(&chan->not_empty, &chan->mtx, timeout);
        if (rv == ETIMEDOUT) {
            pthread_mutex_unlock(&chan->mtx);
            errno = ETIMEDOUT;
            return ETIMEDOUT;
        }
    }
    
    // Check for close with empty queue
    if (chan->len == 0 && chan->is_closed) {
        pthread_mutex_unlock(&chan->mtx);
        errno = EPIPE;
        return EPIPE;
    }
    
    // Dequeue from head
    r_chan_node_t *node = chan->head;
    *msg_out = node->msg;
    chan->head = node->next;
    if (!chan->head) {
        chan->tail = NULL;
    }
    chan->len--;
    
    pthread_mutex_unlock(&chan->mtx);
    
    free(node);
    return 0;
}

// =============================================================================
// Signal Pipe Management
// =============================================================================

void r_chan_drain_signal(r_chan_t *chan) {
    if (!chan || chan->signal_pipe[0] < 0) return;
    
    char buf[64];
    while (read(chan->signal_pipe[0], buf, sizeof(buf)) > 0) {
        // Keep draining
    }
}
