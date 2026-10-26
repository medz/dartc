## Unreleased

- Support simple classes, fields, constructors, and direct instance methods.
- Initialize top-level variables lazily and omit unused native functions.
- Pass additional internal function arguments on the stack.

## 0.1.0

- Compile functions, control flow, strings, lists, and relative imports.
- Build a standalone native compiler that can compile its own Dart sources.
- Generate macOS and Linux ARM64 executables, including local Mach-O signatures in Dart.
- Export explicitly typed FFI callbacks as experimental macOS native libraries.

## 0.0.1

- Compile main and string-literal print calls to standalone macOS ARM64 executables.
