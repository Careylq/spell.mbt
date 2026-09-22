// Native stdin reader for `spell --words -`.
//
// `moonbitlang/x/fs.read_file_to_bytes("/dev/stdin")` sizes its buffer by
// seeking to the end of the stream, which fails with `Illegal seek` when stdin
// is a pipe (docs/MOONBIT_GOTCHAS.md #33). These two functions feed the MoonBit
// side fixed-size chunks read with plain `fread` until EOF, so no seek is ever
// needed. See `read_stdin_bytes` in cmd/main/main.mbt.
//
// Only compiled for the native and llvm targets (see `native-stub` in
// cmd/main/moon.pkg); wasm, wasm-gc and js never see this file.

#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "moonbit.h"

#ifdef __cplusplus
extern "C" {
#endif

// Read up to `capacity` bytes of stdin into `buffer`.
//
// Returns the number of bytes read, `0` at end of input, or `-1` on error
// (`errno` then holds the reason).
MOONBIT_FFI_EXPORT int moonbit_spell_read_stdin_chunk(moonbit_bytes_t buffer,
                                                      int capacity) {
  size_t count = fread(buffer, 1, (size_t)capacity, stdin);
  if (count == 0) {
    return ferror(stdin) ? -1 : 0;
  }
  return (int)count;
}

// `strerror(errno)` as MoonBit `Bytes`, for a human-readable read error.
MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_spell_stdin_error(void) {
  const char *message = strerror(errno);
  size_t len = strlen(message);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, message, len);
  return bytes;
}

#ifdef __cplusplus
}
#endif
