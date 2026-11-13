import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/compiler.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  for (final os in OperatingSystem.values) {
    test(
      'system library selection follows $os and excludes unused symbols',
      () async {
        final compiler = Compiler(
          Target(os, .arm64),
          resources: _Sources(await SdkSources.load()),
        );
        final prefix = os == .macos ? '_' : '';
        for (final (fixture, math) in [
          ('system_libraries.dart', true),
          ('system_library_unused.dart', false),
        ]) {
          final result = await compiler.compile([
            '/__dartc__/sdk/patches/fixtures/$fixture',
          ], output: const .executable());
          final libraries = result.dependencies.cast<SharedLibraryInput>();
          final system = os == .macos
              ? '/usr/lib/libSystem.B.dylib'
              : 'libc.so.6';
          expect(
            libraries.map((library) => library.name),
            unorderedEquals([system, if (math && os == .linux) 'libm.so.6']),
          );
          final symbols = {
            for (final library in libraries)
              library.name: library.symbols.keys.toSet(),
          };
          expect(symbols[system], contains('${prefix}getpid'));
          if (math) {
            expect(
              symbols[os == .macos ? system : 'libm.so.6'],
              contains('${prefix}sin'),
            );
          }
          expect(
            symbols.values.expand((symbols) => symbols),
            isNot(contains('${prefix}dartc_missing_unused_symbol')),
          );
        }
      },
    );
  }
}

final class _Sources(final SdkSources base) extends SdkSources {
  final _fixtures = {
    for (final name in ['system_libraries.dart', 'system_library_unused.dart'])
      'sdk/patches/fixtures/$name': File('test/compiler/fixtures/$name')
          .readAsBytesSync(),
  };
  @override
  Iterable<String> get paths => [...base.paths, ..._fixtures.keys];
  @override
  bool contains(String path) =>
      _fixtures.containsKey(path) || base.contains(path);
  @override
  int? length(String path) => _fixtures[path]?.length ?? base.length(path);
  @override
  Uint8List read(String path) => _fixtures[path] ?? base.read(path);
}
