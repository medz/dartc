# SDK sources

These sources are compiled for the user's target platform. They ship with dartc and need no separate installation.

| Directory | Contents |
| --- | --- |
| `std/` | Unmodified official Dart SDK library sources, license, version and commit. |
| `runtime/` | Dart implementations of allocation, collection, finalization, scheduling and other execution support. |
| `patches/` | Target implementations installed into their owning standard libraries during analysis. |

The compiler and runtime share the declarations in `lib/runtime/contracts.dart` and the memory layout exposed by `lib/layout/memory.dart`. Those files have one source definition and are included when packaging the SDK.

Source execution reads this directory directly. Editing runtime or patches requires no archive regeneration. Standard library contents must match the version, commit and fingerprint in `lib/src/sdk/sdk.dart`; SDK updates replace the official sources and update that pin together. Preserve `std/LICENSE` and the original source headers.

`dart run tool/build.dart` packages the current sources, verifies them and embeds them in the standalone compiler. The archive is a build artifact, not a checked-in input. Native compilation uses the same source interface for directories and embedded archives.

`package:dartc/sdk.dart` exposes `SdkSources.load()` for package execution, `SourceDirectory` for an explicit dartc package directory, and `SourceArchive` for packaged resources. A third-party AOT host supplies either source provider to `Compiler(resources: ...)`; `SourceArchive.encode` creates portable resource bytes. The host owns their delivery and location, so an AOT executable does not depend on package discovery or its working directory.
