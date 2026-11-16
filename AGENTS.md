# Repository Guidelines

## Start and Scope

Start with the [contributor docs](.agents/docs/README.md) and the relevant [task card](.agents/docs/board.md). Read the design and skills needed for the current work. User instructions take precedence; task readiness does not grant authorization. Documentation maintenance does not resume paused compiler work.

## Architecture

- `lib/src/<domain>/` owns an independently usable domain; `lib/<domain>.dart` exposes it. Consume public domain APIs and keep dependencies acyclic.
- `sdk/std/` contains pinned official Dart sources, `sdk/patches/` supplies missing target implementations, and `sdk/runtime/` contains ordinary Dart runtime algorithms. Follow declarations to their actual external leaves before adding patches.
- Implement Dart syntax and observable semantics on the scalar, address, layout, memory and calling foundations shared with FFI. Review existing execution shapes rather than assuming them correct; no surface-API special cases. Validate necessary runtime execution and inferred short paths separately under the [foundation contract](.agents/docs/layout.md#基础能力先统一).
- Preserve static obligations, evaluation order, exceptions, termination, identity and GC roots. Missing implementations or invalid analysis must fail explicitly; genuine runtime uncertainty remains supported.
- Complete responsibilities and contracts. This overrides smallest-diff or preserve-current-structure preferences: compare alternatives when the current architecture obstructs correctness or clarity. Delete replaced code and migrate callers, fixtures, configuration and exports together.

## Development and Validation

Use Dart SDK 3.14 within the package constraint. Use two-space indentation, `lowercase_with_underscores.dart`, primary constructors and contextual dot shorthand where appropriate. Document public contracts with concise Dartdoc.

```sh
dart pub get
dart run bin/dartc.dart --help
dart run tool/build.dart
dart format <changed-files>
dart analyze <changed-paths>
dart test <affected-tests>
```

Tests and fixed fixtures live in `test/<domain>/`; tools prepare assets in `build/` before execution. Follow [test/README.md](test/README.md). Reuse unaffected validation, keep default concurrency, and distinguish cross-generation, emulation and native execution. Benchmark evidence identifies source revision, compiler binary, configuration, workload and platform; diagnostic variants cannot stand in for defaults. Never reformat `sdk/std/` or commit generated ZIP archives.

## Collaboration and Delivery

The primary agent implements the critical path and owns integration and delivery. Coordinate parallel work and independent review under the [workflow](.agents/docs/workflow.md#协作与整合), with clear outputs and edit boundaries. Adapt delegation to the work and available capabilities; continue independent authorized work when another part is blocked.

Keep local and remote branches on `main`; do not create branches or worktrees without a new instruction. Commit and push only within current authorization. Use Conventional Commits; the person completing integration commits, preserving existing authorship without automatic co-authorship or squashing.

## Root Cause and Delivery Gate

- A demonstrated contract or architecture failure requires tracing and addressing its owner before adding another workaround. Prior AI work has no presumption of correctness. Compare the causal fix and replacement costs; neither small patches nor full rewrites are inherently sufficient.
- Do not hide missing semantics behind fallbacks, weaken checks, substitute easier inputs, or present partial/diagnostic evidence as default-product completion. Preserve the original acceptance contract and disclose remaining failures. Withdraw claims contradicted by evidence.
- Before accepting a compiler capability/refactor or architecture/performance completion claim, obtain a non-author review using [dartc-review-delivery](.agents/skills/dartc-review-delivery/SKILL.md). Blocking findings and insufficient evidence prevent claiming delivery or integrating it as accepted work; return to the original task. Follow the [review gate](.agents/docs/workflow.md#独立审查与驳回), without adding a user approval step for authorized repairs.

## Knowledge Ownership

`specs/` alone tracks language contracts, support and gaps; `CHANGELOG.md` records user-visible releases. Shared contracts, plans and skills are versioned for all contributors; use the [ownership index](.agents/docs/README.md#信息归属). Automatically apply [knowledge maintenance](.agents/skills/dartc-maintain-knowledge/SKILL.md) when decisions, verified failures or reusable methods change future work. Update the owner, remove superseded guidance and migrate references in the same delivery. Do not retain historical instructions, duplicate rules or local-only dependencies in current docs; raw research and logs can remain untracked.
