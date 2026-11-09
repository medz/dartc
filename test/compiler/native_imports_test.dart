@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import '../linker/fixtures/shared_libraries.dart';
import 'fixtures/native_imports_ffi.dart';

void main() {
  const source = 'test/compiler/fixtures/native_imports.dart';
  final target = Target.host();
  final compiler = Compiler(target);
  final assets = NativeAssets(target);
  final ObjectFormat format = switch (target.operatingSystem) {
    .macos => MachO(target),
    .linux => Elf(target),
  };
  late NativeImports native;
  setUpAll(() {
    native = NativeImports();
    addTearDown(native.close);
  });

  test(
    'source native calls distinguish assets and preserve boundary conversions',
    () {
      for (final value in [-129, -1, 0, 127, 128, 255, 256]) {
        final narrowed = value.toSigned(8);
        expect(native.run(value), (narrowed + 7) * 1000 + narrowed - 11);
      }
      for (final address in [0, 1, 0x1000, 0x123456789]) {
        expect(native.pointer(Pointer<Void>.fromAddress(address)), address);
      }
    },
  );

  test(
    'missing asset bindings cannot fall through to a matching symbol',
    () async {
      await expectLater(
        compiler.compile(
          [source],
          nativeSymbols: {
            'other': {'step': 'increment'},
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'asset and symbol',
            contains('step in asset math:first'),
          ),
        ),
      );
    },
  );

  test('source native calls load a separate shared provider', () {
    final library = NativeImports('compiler/native_imports_dynamic');
    addTearDown(library.close);
    for (final value in [-129, -1, 0, 127, 128, 255, 256]) {
      final narrowed = value.toSigned(8);
      expect(library.run(value), (narrowed + 7) * 1000 + narrowed - 11);
    }
    expect(
      library.pointer(Pointer<Void>.fromAddress(0x123456789)),
      0x123456789,
    );
  });

  for (final kind in ['object', 'static', 'shared', 'dynamic']) {
    test(
      'native imports compile to $kind output with explicit link inputs',
      () async {
        final library = assets.library(
          kind == 'dynamic'
              ? 'compiler/native_imports_dynamic'
              : 'compiler/native_imports',
        );
        final provider = format.decodeObject(
          assets.file('compiler/native_function_pointers.o').readAsBytesSync(),
        );
        final result = await compiler.compile(
          [source],
          output: switch (kind) {
            'object' => .object(),
            'static' => .staticLibrary(),
            _ => .sharedLibrary(library.uri.pathSegments.last),
          },
          nativeSymbols: nativeImportSymbols,
          linkInputs: [
            if (kind == 'shared') .object(provider),
            if (kind == 'dynamic')
              dependency(target, 'native_function_pointers', {
                for (final name in ['increment', 'decrement', 'opaque'])
                  target.nativeSymbol(name): target.nativeSymbol(name),
              }),
          ],
        );
        final expected = switch (kind) {
          'object' => assets.file('compiler/native_imports.o'),
          'static' => assets.file('compiler/native_imports.a'),
          _ => library,
        };
        expect(result.bytes, expected.readAsBytesSync());
        if (kind == 'object') {
          expect(
            format.decodeObject(result.bytes).imports,
            unorderedEquals(
              ['increment', 'decrement', 'opaque'].map(target.nativeSymbol),
            ),
          );
          await expectLater(
            compiler.compile(
              [source],
              linkInputs: [LinkInput.object(provider)],
            ),
            throwsArgumentError,
          );
        }
      },
    );
  }
}
