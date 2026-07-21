#ifndef RBCFTOOLS_WASM_SOCKET_COMPAT_H
#define RBCFTOOLS_WASM_SOCKET_COMPAT_H

/*
 * Emscripten supplies POSIX read/write but not the socket aliases HTSlib's
 * configure probes may select.  HTSlib's libcurl backend is disabled for
 * webR builds, so mapping these aliases to file-descriptor I/O is sufficient
 * for the remaining local-file code paths.
 */
#ifdef __EMSCRIPTEN__

#include <stddef.h>
#include <sys/types.h>
#include <unistd.h>

static inline ssize_t rbcftools_wasm_recv(int fd, void *buf, size_t len,
                                          int flags) {
  (void)flags;
  return read(fd, buf, len);
}

static inline ssize_t rbcftools_wasm_send(int fd, const void *buf, size_t len,
                                          int flags) {
  (void)flags;
  return write(fd, buf, len);
}

#define recv rbcftools_wasm_recv
#define send rbcftools_wasm_send
#define closesocket close

#endif

#endif
