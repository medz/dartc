# Development

- Keep the implementation direct and small. Use native Dart and avoid unnecessary dependencies or abstractions.
- Work toward genuine native self-hosting. Do not substitute an official-compiler wrapper or interpreter for compiling Dart source to native instructions.
- Keep README and other user documentation focused on installation, supported behavior, and usage. Do not add internal progress logs.
- Test observable behavior through real compilation and execution. Give each behavior one owning test; avoid mocks, source-text assertions, and tests that repeat implementation details.
- Validate inputs at their owning boundary once. Do not add defensive checks or speculative edge-case machinery throughout internal code.
- Do not add production exports, options, or globals solely for tests. Extend an existing behavior test before adding another.
- Keep changes within the requested compiler scope. Commit and push completed working changes directly.
