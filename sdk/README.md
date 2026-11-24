# SDK sources

What programs are compiled with besides their own sources. Nothing here has to be installed or downloaded.

| Directory | Contents |
| --- | --- |
| `std/` | The official Dart SDK libraries, unmodified, with their license, version and commit. |
| `native/` | What completes them for native programs. Each directory patches the library it is named after; directories in it are for one system only. |

The runtime is in `lib/src/heap`, as the library `dart:_heap`.

The compiler merges the official patches for native programs into `std/`, then those in `native/`, in memory (`lib/src/source/patch.dart`). Running from this package reads the files; `dart run tool/build.dart` packs them into the compiler.

To update the SDK, replace `std/` and change the version in `test/source/sdk_test.dart`.
