import 'package:dartc/artifact.dart';
import 'package:dartc/formats.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

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
