# Testing

```sh
dart test                                # everything, on this machine
dart test test/translate -N 'closures'   # some
```

The official `dart` is the oracle. What the programs in `programs` do is told by comments next to their code, which a tool writes and checks with the official `dart`:

```sh
dart run tool/expect.dart                # checks all
dart run tool/expect.dart --update <files>
```

`support/expectations.dart` tells what comments there are. Random programs, and those that use files or C, are compared with the official `dart` when they run.

| Directory | What is tested |
| --- | --- |
| `lir`, `hir`, `graph` | The intermediate representations: printing, verifying, interpreting |
| `source` | Finding errors, patching the libraries |
| `programs` | Dart programs, with what they do |
| `translate` | These programs, by the HIR interpreter, the LIR interpreter, optimized, and compiled; also when collecting at every allocation |
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
