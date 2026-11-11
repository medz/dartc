# Testing

Run the tests for the changed contract and its affected callers. A frontend change usually needs frontend and IR checks; it does not require running the whole suite on every operating system and CPU.

```sh
dart test test/frontend/analysis/pattern_constants_test.dart
dart test test/ir test/assembler
```

Use the standard runner's concurrency. Override `--concurrency` only when measured resource contention calls for it; Docker or CPU emulation alone is not a reason to force serial execution. Keep failures visible rather than increasing global timeouts or retries.

## Test groups

| Command | Coverage | Asset preparation |
| --- | --- | --- |
| `dart test <paths>` | The changed contract and affected callers | Only if the selected suites have the `assets` tag |
| `dart test -P unit` | All suites that need no prebuilt assets | None |
| `dart test -P native` | Host Compiler/CLI integration, standalone compilation and native execution | Current target and host compiler assets |
| `dart test` | All suites on the current host, including all-target file-format checks | All targets |

The `assets` tag marks suites that consume prebuilt files. The `native` tag selects host compilation, output handling and actual FFI calls; the preset lists the participating files and domains. Add new native suites to that preset without including unrelated test files. Keep target-independent assertions outside native suites so they can run without loading a library.

For host execution, build only its assets:

```sh
dart run tool/build_test_assets.dart macos-arm64
dart test -P native
```

The builder also accepts `macos-x64`, `linux-arm64` and `linux-x64`, with multiple targets separated by spaces. With no arguments it builds all supported targets. Sources and FFI clients live in each domain's `fixtures/`; outputs go to `build/test/<target>/`. Each compiler fixture is compiled to an object once per target and binding configuration, then archived and linked through the public object/linker APIs. Compiler and CLI tests separately exercise object, static, shared and executable output requests.

The builder also compiles and packages the real `bin/dartc.dart` executable and builds a fixed Dart FFI client with the development SDK. It prepares a standalone input with explicit package dependencies and an archive for the SDK build-input tests. To prepare only these assets, including executable resource tests, run `dart run tool/build_compiler_test_assets.dart`. The builder reads the bundled SDK data and needs no source download. Acquisition tests serve their prepared archive over loopback, checking content integrity, invalid archives and interrupted preparation.

The standalone test invokes the prepared dartc executable with an empty `PATH` and no inherited environment, then uses the prepared FFI client to execute its library output. It also compiles and launches a standalone executable. This compilation is the behavior under test. For full environment isolation, copy only those executables and the prepared input to a container without an SDK, checkout or source caches and run with `--network none`.

Build assets before tests. A missing asset is an error, never a request to compile from a test setup. Rebuild when its source, compiler, dependency or target configuration changes. The same batch of target assets can be copied into matching execution environments; do not rebuild all targets in every container. Host compiler checks still compile source in that host.

For example, execute Linux ARM64 tests using assets built on the current machine. The container uses a separate package configuration and cannot change the checkout:

```sh
dart run tool/build_test_assets.dart linux-arm64
docker run --rm --platform linux/arm64 \
  -e TEST_TARGET=linux-arm64 -v "$PWD:/src:ro" \
  --tmpfs /work:exec -w /work dart:3.13.7-sdk sh -eu -c '
    cp -R /src/lib /src/bin /src/test /src/tool /work/
    cp /src/pubspec.yaml /src/pubspec.lock /src/analysis_options.yaml /src/dart_test.yaml /src/LICENSE /work/
    mkdir -p build/test
    cp -R /src/build/test/$TEST_TARGET build/test/
    dart pub get
    dart run tool/build_compiler_test_assets.dart
    dart test -P native
  '
```

For Linux x64, use `linux-x64` for the builder and `TEST_TARGET`, and `linux/amd64` for Docker. Reuse an existing build from the same source revision instead of running the builder again.

## Validation scope

| Change | Required checks |
| --- | --- |
| Frontend, constants, lowering, IR | Relevant semantic and contract tests on one host; add native cases when emitted behavior changes |
| Instruction encoding, object records, relocations | All affected target variants on one host; cross-generation is not execution |
| Calling conventions, register allocation, memory operations, linking/loading | Relevant native tests on every affected OS/CPU; shared rules can affect all targets |
| Bundled SDK, CLI, filesystem handling | Relevant host integration tests on the affected operating systems |
| Dependency upgrades, broad integration, release candidates | Full host regression and the platform execution required by the changed dependencies and supported release targets |

Do not repeat a passed check unless its inputs changed or a new failure calls its result into question. A commit or push alone is not a reason to rerun it. CI covers required environments that local machines and Docker cannot establish; it is not a per-edit requirement. Record emulated execution separately from real hardware and do not use it for native performance claims.

## Test ownership

Test each domain's public contract. End-to-end tests check the compiler's handoffs and observable behavior, rather than repeating every unit assertion. Remove matrix dimensions that cannot affect the contract, but retain different binary formats, operand constraints and platform calling conventions.

Reuse expensive, read-only analysis within a suite when appropriate. Keep mutable execution state isolated, and open resources in test callbacks or setup hooks, with matching teardown. Registering tests must not load native libraries or read generated assets. Expected language behavior follows the applicable specification and library contracts; investigate SDK differences before adopting their output as an expectation.

Use the runner's [path and tag selection](https://dart.dev/tools/dart-test), [configuration presets](https://github.com/dart-lang/test/blob/master/pkgs/test/doc/configuration.md#configuration-presets) and, when timing needs investigation, its JSON reporter. No separate test orchestration framework is required.
