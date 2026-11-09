import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/linker.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import 'fixtures/calls.dart';
import 'fixtures/data.dart';

void main() {
  test('shared dependencies own their bindings and reject invalid names', () {
    final names = {'local': 'native'};
    final input = SharedLibraryInput('provider', symbols: names);
    names.clear();
    expect(input.symbols, {'local': 'native'});
    expect(() => input.symbols.clear(), throwsUnsupportedError);
    for (final invalid in ['', 'nul\u0000suffix']) {
      expect(() => LinkInput.sharedLibrary(invalid), throwsArgumentError);
      expect(
        () => LinkInput.sharedLibrary('valid', symbols: {invalid: 'valid'}),
        throwsArgumentError,
      );
      expect(
        () => LinkInput.sharedLibrary('valid', symbols: {'valid': invalid}),
        throwsArgumentError,
      );
    }
  });

  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final Linker linker = os == .macos
          ? MachOLinker(target)
          : ElfLinker(target);
      final modules = callModules(target), name = modules.first.imports.single;

      if (os == .macos) {
        test('$target rejects unrepresentable library ordinals', () {
          expect(
            () => linker.linkSharedLibrary([
              .object(modules.last),
              for (var i = 0; i < 253; i++) .sharedLibrary('provider$i'),
            ], name: 'consumer'),
            throwsUnsupportedError,
          );
        });
      }

      test(
        '$target rejects conflicting bindings and direct dynamic address references',
        () {
          expect(
            () => linker.linkSharedLibrary([
              .object(modules.first),
              .sharedLibrary('first', symbols: {name: 'native'}),
              .sharedLibrary('second', symbols: {name: 'native'}),
            ], name: 'consumer'),
            throwsArgumentError,
          );
          final data = dataModules(target).last;
          expect(
            () => linker.linkSharedLibrary([
              .object(data),
              .sharedLibrary(
                'provider',
                symbols: {for (final name in data.imports) name: name},
              ),
            ], name: 'consumer'),
            throwsUnsupportedError,
          );
          expect(
            () => linker.linkSharedLibrary([
              .object(modules.first),
              .sharedLibrary('provider', symbols: {'other': 'native'}),
            ], name: 'consumer'),
            throwsArgumentError,
          );
        },
      );

      test(
        '$target prefers included definitions and coalesces identical dependencies',
        () {
          final inputs = modules.map(LinkInput.object).toList();
          final first = linker.linkSharedLibrary([
            ...inputs,
            .sharedLibrary('provider'),
          ], name: 'consumer');
          expect(
            linker.linkSharedLibrary([
              ...inputs,
              .sharedLibrary('provider', symbols: {name: 'not_used'}),
              .sharedLibrary('provider', symbols: {name: 'not_used'}),
            ], name: 'consumer'),
            first,
          );
        },
      );

      test(
        '$target emits ordered dependencies and writable pointer bindings',
        () {
          final inputs = <LinkInput>[
            if (os == .macos) .sharedLibrary('/usr/lib/libSystem.B.dylib'),
            .object(modules.first),
            .object(
              ObjectModule(target, [
                Section.readOnlyData([1]),
                Section.data(Uint8List(256), alignment: 128),
              ], []),
            ),
            for (var i = 1; i <= 16; i++)
              .sharedLibrary(
                'provider$i',
                symbols: {if (i == 16) name: 'actual'},
              ),
          ];
          final bytes = linker.linkSharedLibrary(inputs, name: 'consumer');
          expect(linker.linkSharedLibrary(inputs, name: 'consumer'), bytes);
          final data = ByteData.sublistView(bytes);
          String stringAt(int start) =>
              utf8.decode(bytes.sublist(start, bytes.indexOf(0, start)));
          if (os == .linux) {
            var dynamic = -1, writableStart = -1, writableEnd = -1;
            for (var i = 0; i < data.getUint16(56, .little); i++) {
              final base = 64 + i * 56;
              final type = data.getUint32(base, .little);
              if (type == 2) dynamic = data.getUint64(base + 8, .little);
              if (type == 1 && data.getUint32(base + 4, .little) == 6) {
                writableStart = data.getUint64(base + 16, .little);
                writableEnd =
                    writableStart + data.getUint64(base + 40, .little);
              }
            }
            expect(dynamic, isNonNegative);
            final tags = <int, int>{}, needed = <int>[];
            for (var at = dynamic; data.getUint64(at, .little) != 0; at += 16) {
              final tag = data.getUint64(at, .little),
                  value = data.getUint64(at + 8, .little);
              if (tag == 1) needed.add(value);
              tags[tag] = value;
            }
            expect(needed.map((offset) => stringAt(tags[5]! + offset)), [
              for (var i = 1; i <= 16; i++) 'provider$i',
            ]);
            expect(tags[8], 24);
            expect(tags[9], 24);
            final relocation = tags[7]!;
            expect(data.getUint64(relocation, .little), writableStart + 256);
            expect(
              data.getUint64(relocation, .little) + 8,
              lessThanOrEqualTo(writableEnd),
            );
            expect(
              data.getUint64(relocation + 8, .little),
              (2 << 32) | (arch == .arm64 ? 1025 : 6),
            );
            expect(data.getInt64(relocation + 16, .little), 0);
            final symbol = tags[6]! + 2 * 24;
            expect(
              stringAt(tags[5]! + data.getUint32(symbol, .little)),
              'actual',
            );
            expect(data.getUint8(symbol + 4), 0x12);
            expect(data.getUint16(symbol + 6, .little), 0);
          } else {
            final dependencies = <String>[];
            var bind = -1, bindSize = -1, symtab = -1;
            var at = 32;
            for (var i = 0; i < data.getUint32(16, .little); i++) {
              switch (data.getUint32(at, .little)) {
                case 0xc:
                  dependencies.add(
                    stringAt(at + data.getUint32(at + 8, .little)),
                  );
                case 0x80000022:
                  bind = data.getUint32(at + 16, .little);
                  bindSize = data.getUint32(at + 20, .little);
                case 2:
                  symtab = data.getUint32(at + 8, .little);
                  expect(data.getUint32(at + 12, .little), 2);
              }
              at += data.getUint32(at + 4, .little);
            }
            expect(at, 32 + data.getUint32(20, .little));
            expect(dependencies, [
              '/usr/lib/libSystem.B.dylib',
              for (var i = 1; i <= 16; i++) 'provider$i',
            ]);
            expect(bind, isNonNegative);
            expect(bind % 8, 0);
            expect(bytes.sublist(bind, bind + bindSize), [
              0x20,
              17,
              0x40,
              ...utf8.encode('actual'),
              0,
              0x51,
              0x72,
              0x80,
              2,
              0x90,
              0,
            ]);
            expect(data.getUint8(symtab + 16 + 4), 1);
            expect(data.getUint16(symtab + 16 + 6, .little), 17 << 8);
          }
        },
      );
    }
  }
}
