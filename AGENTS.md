# Development

- Keep the implementation direct and small. Use native Dart and avoid unnecessary dependencies or abstractions.
- Keep module ownership explicit. Import definitions from their owning files; do not hide internal dependencies behind barrel exports.
- Work toward genuine native self-hosting. Do not substitute an official-compiler wrapper or interpreter for compiling Dart source to native instructions.
- Keep README and other user documentation focused on installation, supported behavior, and usage. Do not add internal progress logs.
- Test observable behavior through real compilation and execution. Give each behavior one owning test; avoid mocks, source-text assertions, and tests that repeat implementation details.
- Validate inputs at their owning boundary once. Do not add defensive checks or speculative edge-case machinery throughout internal code.
- Do not add production exports, options, or globals solely for tests. Extend an existing behavior test before adding another.
- Keep changes within the requested compiler scope. Commit and push completed working changes directly.

- Follow doc/architecture.md as an evolving target. Self-hosting a subset is a milestone, not completion of the compiler or runtime design.
- Plan language work from specs/ and update its upstream clause references, implementation gaps, and behavior-test evidence with each language change. Keep language compatibility details there; keep doc/architecture.md focused on compiler and runtime design.
- Keep compiler and runtime algorithms expressible and replaceable in Dart. Reuse FFI types and layouts; concentrate unavoidable machine-specific capabilities in a small explicit primitive boundary.
- Bootstrap new language features and primitives in two steps: build compiler support using old capabilities, then adopt them in compiler or runtime code and rebuild. Use them where they simplify existing code; measure the same workload before claiming performance gains.
