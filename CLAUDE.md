# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

dartc is an ahead-of-time compiler for Dart, written in Dart. It makes executables, object files, static and shared libraries for macOS ARM64, Linux ARM64 and Linux x64, without a C compiler or linker. Use Dart SDK 3.14.0.

`ARCHITECTURE.md` (in Chinese) has the design and the decisions behind it; `PLAN.md` (in Chinese) has the progress and known limits. What is not done is in the GitHub issues. Read the matching rows of ARCHITECTURE §5 before changing how something works, and update them when it changes.

## Commands

```sh
dart run bin/dartc.dart hello.dart -o hello     # compile; see --help
dart run tool/build.dart                        # build/dartc, one program with the SDK inside
dart analyze --fatal-infos                      # has to be clean
dart test                                       # everything; about 10 minutes
dart test test/translate/closures_test.dart     # one file
dart test test/translate -N 'part of a name'    # by name; -n takes a regular expression
dart run tool/measure.dart [names] [-inline] [-devirtualize]  # time against official AOT
```

Tests run compiled programs on macOS ARM64. For Linux, give two containers with glibc 2.34 or later and gcc, in which the directory for temporary files has the same path as on the host:

```sh
DARTC_TARGETS=linuxArm64,linuxX64 DARTC_LINUX_ARM64=<container> DARTC_LINUX_X64=<container> \
  dart test test/driver test/translate
```

Format files one by one. Never format `sdk/std`, which is the unmodified official source.

## Rules of the design

- **The official `dart` is the oracle.** Tests run each program with it and compare output and exit code; expectations are not written from memory.
- **Correctness does not depend on optimization.** Without any optimization, programs compile and run right. Nothing may need facts about the whole program's heap, and every stage ends for a stated reason, not by a budget or timeout.
- **What is not supported is refused** with its position (`Not supported yet: …`). Never guess or generate code that may be wrong. A static error must stop compilation whatever comments or `analysis_options.yaml` say.
- Later stages never ask earlier ones to start again.
- Files have at most 600 lines, functions at most 80. No code for features that are not there yet.

## Pipeline

```text
source ─▶ translate (with world) ─▶ HIR ─▶ optimize ─▶ lower ─▶ LIR ─▶ emit ─▶ image
analyzer   AST → HIR, on demand         optional     once per function  machine code  files
```

Each directory `lib/src/<domain>` has one public entry `lib/<domain>.dart`. Domains import only these entries, along the edges that `test/domain_dependencies_test.dart` lists; there are no import cycles and no `part` files. `driver` runs the stages and has the command (`command.dart`). `lib/compiler.dart` and `lib/interop.dart` are what other packages use.

- **`source`** merges three layers of the standard libraries in memory: `sdk/std` (official), the official patches for native programs, and `sdk/native/<library>/` (ours, with subdirectories for one system or target). It then resolves everything with the analyzer, from overlays only. `corrections.dart` gives the analyzer other text where it evaluates constants differently from the official compiler; positions are mapped back.
- **`translate`** translates what `main` (or the `@Export`s) reach. `ProgramTranslator` repeats until no new functions, dispatch entries, closures or classes appear. `ProgramScope` is what the parts see of the program; `FunctionBuilder` builds one function; `Conversions` is the only place that changes representations and tests types. A value is always represented by its static type: `int`, `double` and `bool` unboxed, everything else a reference.
- **HIR** knows Dart classes, fields, selectors and exceptions. **LIR** has four types (`i64`, `f64`, `ref`, `ptr`), SSA with block parameters, and no hidden checks. Both have a verifier, a printer and an interpreter.
- **`optimize`** rewrites each function a fixed number of times. Each optimization can be turned off.
- **`heap`** is the runtime (collector, unwinding, types, numbers). It is plain Dart, compiled with the program as `dart:_heap`; the functions in its `machine.dart` and `objects.dart` each become one operation. The collector never moves objects. Roots come from stack maps at calls.
- **`emit`** selects instructions and allocates registers; only `arm64/` and `x64/` know the machine. **`native`** has C layouts and calling conventions, chosen by `Target`. **`image`** writes Mach-O and ELF.

The runtime finds functions of the libraries by their private names: `_scope.runtime('throwCast')` is `_throwCast`, somewhere in `sdk/native` or `lib/src/heap`. Such names have to be unique across libraries.

## Tests

`agrees(name, source)` in `test/translate/support.dart` is the main tool. It runs a program with the official `dart`, the HIR interpreter, the LIR interpreter, the interpreter after optimizing, and compiled, also when collecting before every allocation. When levels disagree, the first one that differs has the bug. Use `isLong: true` for programs that depend on time or create too much to always collect.

The text of stack traces is not compared. `test/driver/random_*.dart` generate programs; new seeds are a good check after changes to `translate` or `optimize`.

New IR instructions need printing, verifying and interpreting, with tests that are accepted and refused.

## Style

Code uses Dart 3.14 features throughout: primary constructors, dot shorthands, null-aware elements, records and patterns. Comments and messages are short sentences in plain English that say what something is for. Commits follow Conventional Commits.
