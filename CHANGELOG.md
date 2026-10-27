## 0.2.0

Early preview release for macOS and Linux ARM64.

- Provide standalone native compiler archives with compatible runtime sources.
- Support simple classes, accessors, nullable/reified value checks, canonical const instances and lazy top-level initialization.
- Add noncapturing local and anonymous functions, structural function types and nongeneric type aliases.
- Resolve package configuration v2, language versions, file/package URIs, conditional imports and library parts.
- Check runtime NoGC contracts and retain runtime components according to actual dependencies.

Captures, inheritance, general generics, exceptions, async code and most SDK libraries remain unsupported. Runtime sources and native compiler binaries from older releases must not be mixed with this version.

## 0.1.0

- Compile functions, control flow, strings, lists, and relative imports.
- Build a standalone native compiler that can compile its own Dart sources.
- Generate macOS and Linux ARM64 executables, including local Mach-O signatures in Dart.
- Export explicitly typed FFI callbacks as experimental macOS native libraries.

## 0.0.1

- Compile main and string-literal print calls to standalone macOS ARM64 executables.
