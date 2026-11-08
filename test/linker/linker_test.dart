import 'package:dartc/artifact.dart';
import 'package:dartc/formats.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import 'fixtures/calls.dart';

void main() {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final ImageFormat format = os == .macos ? MachO(target) : Elf(target);
      final linker = Linker(format);
      final code = arch == .arm64 ? [0xc0, 0x03, 0x5f, 0xd6] : [0xc3];
      final module = ObjectModule(target, code, [
        Symbol('entry', 0, code.length, exported: true),
      ]);

      test('$target links and encodes deterministically without file IO', () {
        final first = linker.link([module], libraryName: 'values');
        final second = linker.link([module], libraryName: 'values');
        expect(first.code, module.code);
        expect(format.encodeImage(second), format.encodeImage(first));
        final archive = ArchiveWriter(format);
        expect(archive.encode([module]), archive.encode([module]));
      });

      test(
        '$target rejects unresolved calls and consumes one format layout',
        () {
          final modules = callModules(target);
          expect(
            () => linker.link([modules.first], libraryName: 'missing'),
            throwsArgumentError,
          );
          expect(
            () => format.layoutImage(modules.first, libraryName: 'unlinked'),
            throwsArgumentError,
          );
          final image = linker.link(modules, libraryName: 'calls');
          expect(image.layout.module.imports, isEmpty);
          expect(image.layout.module.relocations, isEmpty);
          expect(image.code, isNot(image.layout.module.code));
          final offset = image.layout.codeOffset;
          expect(
            format
                .encodeImage(image)
                .sublist(offset, offset + image.code.length),
            image.code,
          );
        },
      );

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
              () => linker.link(inputs, libraryName: 'values'),
              throwsArgumentError,
            );
          }
          for (final name in ['', 'bad\u0000name']) {
            expect(
              () => linker.link([module], libraryName: name),
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
          final linked = linker.link([
            local,
            local,
            module,
          ], libraryName: 'values');
          expect(linked.layout.module.symbols.length, 3);
          expect(
            linked.layout.module.symbols.where((s) => s.exported).length,
            1,
          );
          expect(() => format.encodeObject(other), throwsArgumentError);
        },
      );
    }
  }
}
