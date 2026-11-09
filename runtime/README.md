# Target support sources

These Dart libraries are compiled into target programs. They use ordinary Dart control flow and `dart:ffi` declarations; they do not import the host compiler or its code emitters. They are separate from the official standard library sources selected by `DartSdk`.

`platform/io.dart` provides `writeDescriptor(descriptor, bytes, count)` for macOS and Linux glibc on ARM64 and x86-64. It returns the number of bytes written, including short writes and zero progress, or the negative native errno. It retries `EINTR` without repeating a successful partial write. Invalid descriptor ranges return `-EBADF`; negative counts return `-EINVAL`. The caller owns the descriptor and must keep the buffer readable for the requested length. Blocking, signal delivery and durability follow the operating-system contract.

Compile this file as an ordinary source dependency and supply explicit native bindings through `Compiler.compile(nativeSymbols: ..., linkInputs: ...)`:

| Asset | Requested symbol | macOS system symbol | Linux glibc symbol |
| --- | --- | --- | --- |
| `dartc:posix` | `dartc_posix_write` | `write` in `/usr/lib/libSystem.B.dylib` | `write` in `libc.so.6` |
| `dartc:posix` | `dartc_posix_errno` | `__error` in `/usr/lib/libSystem.B.dylib` | `__errno_location` in `libc.so.6` |

The declarations use the supported LP64 layouts: a 32-bit descriptor and errno, 64-bit `ssize_t`/`size_t`, and native pointers. `nativeSymbols` uses undecorated names; `LinkInput.sharedLibrary` uses target-decorated object and native names.

Automatic target-source selection and version verification remain unimplemented. This library does not supply Dart I/O exceptions, scheduling, startup or the complete `dart:io` implementation. Its [fixed native tests](../test/runtime/io_test.dart) exercise actual pipe writes and scripted interruption, short-write and error results.
