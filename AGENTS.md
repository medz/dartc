# Development

- `lib/src/legacy/` is frozen reference and recovery code. Do not modify it or run legacy tests, benchmarks, bootstrap validation or package validation. Preserve existing native seeds and published release assets.
- Keep the implementation direct and small. Use native Dart and avoid unnecessary dependencies or abstractions.
- Keep module ownership explicit. Import definitions from their owning files; do not hide internal dependencies behind barrel exports.
- Work toward genuine native self-hosting. Do not substitute an official-compiler wrapper or interpreter for compiling Dart source to native instructions.
- Build a complete independent Dart compiler. Missing semantics are implementation gaps; preview releases and compiler self-rebuilds do not reduce the language or runtime goals.
- Keep README and other user documentation focused on installation, supported behavior, and usage. Do not add development diaries, per-increment summaries, temporary build/test records or one-off benchmark results to committed Markdown. Keep CHANGELOG limited to user-facing release changes.
- Test observable behavior through real compilation and execution. Give each behavior one owning test; avoid mocks, source-text assertions, and tests that repeat implementation details.
- Validate inputs at their owning boundary once. Do not add defensive checks or speculative edge-case machinery throughout internal code.
- Do not add production exports, options, or globals solely for tests. Extend an existing behavior test before adding another.
- Keep changes within the requested compiler scope. Commit and push completed working changes directly.
- Give parallel tasks non-overlapping file ownership and integrate verified increments through main. Freeze compiler/runtime inputs during bootstrap and benchmarks; prepare pending changes as local patches when those inputs are in use.

- Use doc/architecture.md as a revisable design, including its planned file layout. IR, algorithms, representations and GC choices may change; preserve Dart semantics, explicit phase contracts and a recoverable native build chain. Split files by responsibility without prebuilding empty directories.
- Consult design research for concrete implementation questions. Update the owning documentation and constraints when evidence changes a decision; investigate a specific uncertainty when needed rather than expanding research indefinitely.
- Plan language work from specs/ and update its upstream clause references, current implementation status, concrete gaps, and owning behavior-test entry points with each language change. Track current conformance rather than a chronological history. Keep language compatibility details there; keep doc/architecture.md focused on compiler and runtime design and contracts.
- Keep compiler and runtime algorithms expressible and replaceable in Dart. Reuse FFI types and layouts; concentrate unavoidable machine-specific capabilities in a small explicit primitive boundary.
- Bootstrap new language features and primitives in two steps: build compiler support using old capabilities, then adopt them in compiler or runtime code and rebuild. Use them where they simplify existing code; measure the same workload before claiming performance gains.
- Separate the compiler's host runtime from its target ABI. Preserve matching seed, runtime, layout and standard-library dependencies; introduce a bridge only when a real incompatible change needs one.
