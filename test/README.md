# Testing

```sh
dart test                                # everything, on this machine
dart test test/translate -N 'closures'   # some
```

The official `dart` is the oracle: each program is run with it, and its output and exit code are compared with what dartc gives at every level. Nothing is expected from memory.

| Directory | What is tested |
| --- | --- |
| `lir`, `hir`, `graph` | The intermediate representations: printing, verifying, interpreting |
| `source` | Finding errors, patching the libraries |
| `translate` | Dart programs, by the HIR interpreter, the LIR interpreter, optimized, and compiled; also when collecting at every allocation |
| `world`, `optimize`, `lower`, `heap` | These parts by themselves |
| `emit` | Encoded instructions, and machine code against the LIR interpreter |
| `image` | Object files, executables and libraries, checked with the tools of the system |
| `driver` | Compiled programs, libraries used from C, `dart:ffi`, `dart:io`, random programs, the command |

Tests that run compiled programs do so on macOS ARM64. For Linux, give containers with glibc 2.34 or later and gcc, in which the directory for temporary files has the same path as here:

```sh
DARTC_TARGETS=linuxArm64,linuxX64 \
DARTC_LINUX_ARM64=<container> DARTC_LINUX_X64=<container> \
  dart test test/driver test/translate
```

`tool/measure.dart` compares the time of the programs in `tool/bench/programs` with the official AOT compiler.
