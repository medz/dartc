# Developer tooling

`lib/src/legacy/` is frozen reference and recovery code. Its tests, benchmarks, bootstrap validation and CI workflow are retired. Keep matching native seeds and source revisions; no legacy validation runs are required.

## Native builds

Use an existing native seed matching the source revision. Place it at `build/dartc-seed`, then run these commands from the repository root:

```sh
mkdir -p build
build/dartc-seed tool/bundle_compiler.dart --std lib/src/legacy/runtime.dart -o build/bundle_compiler
build/bundle_compiler "$PWD" build/compiler.dart
build/dartc-seed build/compiler.dart --std lib/src/legacy/runtime.dart -o build/dartc
```

The native seed compiles the source bundler. That bundler generates an ordinary Dart entry containing the runtime and standard-library source dependencies. The final command compiles the entry into a standalone native compiler. These commands do not run tests or replace the preserved seed.

Regenerate `build/compiler.dart` after moving the checkout because its imports contain source paths. If no matching seed exists, use the explicit [cold-start instructions](../../../README.md#build-from-source). An existing seed's failure must not trigger an official-compiler fallback.

## Native archives

Create an archive from a native compiler built for the current host:

```sh
dart tool/package_release.dart --compiler build/dartc
```

The tool copies the binary, license and usage notes into a tar archive and writes its SHA-256 checksum under `build/release/`. It does not execute the compiler or validate the archive. Existing GitHub and pub.dev releases and assets remain available.

## Release notes

Keep `CHANGELOG.md` newest first. Each version has a date, a comparison link and a short description of its user-visible scope. Group entries under Features, Fixes and Upgrade headings as needed; omit empty sections. Combine related commits into one behavior change, and describe fixes by their trigger and observable result.

A GitHub Release starts with what the version enables, then expands its main capabilities with short runnable examples. Follow with upgrade steps, platform downloads, installation instructions and links to the full changelog and versioned specs. Patch releases can use a shorter form. Keep the release and changelog consistent without repeating every entry.

Keep each prose paragraph, list item and blockquote paragraph on one source line so the page can wrap it to the available width. Preserve structural newlines in headings, lists, tables and code blocks.

Explain breaking changes before the examples when users must act. State the affected versions and the concrete replacement or migration step. For compiler/runtime changes, identify the matching archive or bootstrap seed. Validate every example with the reference SDK and the native compiler before publication.

Only include performance claims backed by the same task and necessary side effects; name the compared versions, platform and measurement scope. Keep raw measurements, build logs and validation records in `build/`. Internal refactors belong in release notes only when their user-visible effect can be explained. Language conformance and gaps remain owned by `specs/`.
