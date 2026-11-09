import 'dart:typed_data';

import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import 'fixtures/calls.dart';

void main() {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final ObjectFormat format = os == .macos ? MachO(target) : Elf(target);
      final Linker linker = os == .macos
          ? MachOLinker(target)
          : ElfLinker(target);
      final code = arch == .arm64 ? [0xc0, 0x03, 0x5f, 0xd6] : [0xc3];
      final module = ObjectModule(target, code, [
        Symbol('entry', 0, code.length, exported: true),
      ]);
      Uint8List codeOf(Uint8List image) {
        final data = ByteData.sublistView(image);
        final section = os == .macos ? 104 : data.getUint64(40, .little) + 64;
        final offset = os == .macos
            ? data.getUint32(section + 48, .little)
            : data.getUint64(section + 24, .little);
        final size = data.getUint64(
          section + (os == .macos ? 40 : 32),
          .little,
        );
        return Uint8List.sublistView(image, offset, offset + size);
      }

      test(
        '$target returns a deterministic complete image without file IO',
        () {
          final first = linker.linkSharedLibrary([module], name: 'values');
          final second = linker.linkSharedLibrary([module], name: 'values');
          expect(codeOf(first), module.code);
          expect(second, first);
          expect(() => first[0] = 0, throwsUnsupportedError);
          final archive = ArchiveWriter(format);
          expect(archive.encode([module]), archive.encode([module]));
        },
      );

      test('$target resolves calls without changing input objects', () {
        final modules = callModules(target);
        final before = [for (final module in modules) module.code.toList()];
        expect(
          () => linker.linkSharedLibrary([modules.first], name: 'missing'),
          throwsArgumentError,
        );
        final bytes = codeOf(linker.linkSharedLibrary(modules, name: 'calls'));
        expect(bytes, isNot(modules.first.code));
        expect(modules.map((module) => module.code), before);
        expect(modules.first.imports, isNotEmpty);
        expect(
          modules.every((module) => module.relocations.isNotEmpty),
          isTrue,
        );
      });

      test(
        '$target validates inputs and distinguishes locals from exports',
        () {
          final other = ObjectModule(
            Target(os == .macos ? .linux : .macos, arch),
            code,
            [],
          );
          for (final inputs in [
            <ObjectModule>[],
            [module, other],
            [module, module],
          ]) {
            expect(
              () => linker.linkSharedLibrary(inputs, name: 'values'),
              throwsArgumentError,
            );
          }
          for (final name in ['', 'bad\u0000name']) {
            expect(
              () => linker.linkSharedLibrary([module], name: name),
              throwsArgumentError,
            );
          }
          expect(() => ArchiveWriter(format).encode([]), throwsArgumentError);
          expect(
            () => ArchiveWriter(format).encode([module, other]),
            throwsArgumentError,
          );
          final local = ObjectModule(target, code, [
            Symbol('entry', 0, code.length, binding: .local),
          ]);
          final image = linker.linkSharedLibrary([
            local,
            local,
            module,
          ], name: 'values');
          final body = codeOf(image);
          for (final offset in [0, 16, 32]) {
            expect(body.sublist(offset, offset + code.length), code);
          }
          final data = ByteData.sublistView(image);
          if (os == .linux) {
            final symbols = data.getUint64(40, .little) + 2 * 64;
            expect(data.getUint64(symbols + 32, .little), 2 * 24);
          } else {
            var offset = 32, symbols = -1;
            for (var i = 0; i < data.getUint32(16, .little); i++) {
              if (data.getUint32(offset, .little) == 2) {
                symbols = data.getUint32(offset + 12, .little);
              }
              offset += data.getUint32(offset + 4, .little);
            }
            expect(symbols, 1);
          }
          expect(() => format.encodeObject(other), throwsArgumentError);
        },
      );
    }
  }
  test('linker implementations reject incompatible output platforms', () {
    expect(() => ElfLinker(const Target(.macos, .arm64)), throwsArgumentError);
    expect(() => MachOLinker(const Target(.linux, .x64)), throwsArgumentError);
  });
}
