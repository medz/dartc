import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/functions.dart';

void main() {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch), assets = NativeAssets(target);
      final ObjectFormat format = os == .macos ? MachO(target) : Elf(target);
      final Linker linker = os == .macos
          ? MachOLinker(target)
          : ElfLinker(target);
      ObjectModule defines(
        Map<String, int> values, [
        List<String> imports = const [],
      ]) {
        final module = functions(target, values);
        return ObjectModule(
          target,
          module.sections,
          module.symbols,
          imports: imports.map(target.nativeSymbol),
        );
      }

      Archive archive(List<ObjectModule> modules) =>
          Archive.decode(ArchiveWriter(format).encode(modules));
      final root = defines({'root': 0}, ['dep']), dep = defines({'dep': 42});

      test('$target relinks fixed objects and lazy archive members', () {
        final root = format.decodeObject(
          assets.file('linker/lazy_0.o').readAsBytesSync(),
        );
        final archive = Archive.decode(
          assets.file('linker/lazy.a').readAsBytesSync(),
        );
        final library = assets.library('linker/archive_calls');
        final name = library.uri.pathSegments.last;
        final bytes = linker.linkSharedLibrary([
          .object(root),
          .archive(archive),
        ], name: name);
        expect(bytes, library.readAsBytesSync());
        expect(
          bytes,
          linker.linkSharedLibrary([
            .object(root),
            for (final index in [1, 0])
              .object(format.decodeObject(archive.members[index].bytes)),
          ], name: name),
        );
        expect(
          () => linker.linkSharedLibrary([.archive(archive)], name: name),
          throwsArgumentError,
        );
      });

      test('$target applies target input order and explicit object rules', () {
        final library = archive([dep]);
        final expected = linker.linkSharedLibrary([
          .object(root),
          .object(dep),
        ], name: 'order');
        expect(
          linker.linkSharedLibrary([
            .object(root),
            .archive(library),
            .archive(library),
          ], name: 'order'),
          expected,
        );
        for (final inputs in <List<LinkInput>>[
          [.archive(library), .object(root)],
          [.object(root), .archive(library), .object(dep)],
        ]) {
          if (os == .macos) {
            expect(linker.linkSharedLibrary(inputs, name: 'order'), expected);
          } else {
            expect(
              () => linker.linkSharedLibrary(inputs, name: 'order'),
              throwsArgumentError,
            );
          }
        }
      });

      test(
        '$target resolves cross-archive backreferences with the required rescan',
        () {
          final caller = defines({'caller': 0}, ['entry']);
          final entry = defines({'entry': 1}, ['dep']);
          final first = archive([dep]), second = archive([entry]);
          final inputs = <LinkInput>[
            .object(caller),
            .archive(first),
            .archive(second),
          ];
          final expected = linker.linkSharedLibrary([
            .object(caller),
            .object(entry),
            .object(dep),
          ], name: 'rescan');
          if (os == .linux) {
            expect(
              () => linker.linkSharedLibrary(inputs, name: 'rescan'),
              throwsArgumentError,
            );
          } else {
            expect(linker.linkSharedLibrary(inputs, name: 'rescan'), expected);
          }
          expect(
            linker.linkSharedLibrary([
              ...inputs,
              .archive(first),
            ], name: 'rescan'),
            expected,
          );
        },
      );

      test(
        '$target preserves archive index order when new imports meet duplicate candidates',
        () {
          final caller = defines({'caller': 0}, ['entry']);
          final entry = defines({'entry': 1}, ['dep']);
          final later = defines({'dep': 99});
          final library = archive([dep, entry, later]);
          expect(
            linker.linkSharedLibrary([
              .object(caller),
              .archive(library),
            ], name: 'duplicates'),
            linker.linkSharedLibrary([
              .object(caller),
              .object(entry),
              .object(os == .linux ? later : dep),
            ], name: 'duplicates'),
          );
        },
      );

      test(
        '$target validates selected members and ignores unused object contents',
        () {
          final unused = defines({'unused': 99});
          final encoded = ArchiveWriter(format).encode([dep, unused]);
          final offset = Archive.decode(encoded)
              .members
              .last
              .bytes
              .offsetInBytes;
          final expected = linker.linkSharedLibrary([
            .object(root),
            .object(dep),
          ], name: 'isolated');
          final needsUnused = defines({'root': 0}, ['unused']);
          for (final corrupt in [false, true]) {
            final bytes = Uint8List.fromList(encoded),
                data = ByteData.sublistView(bytes);
            if (corrupt) {
              bytes[offset] = 0;
            } else if (os == .macos) {
              data.setUint32(
                offset + 4,
                arch == .arm64 ? 0x1000007 : 0x100000c,
                .little,
              );
            } else {
              data.setUint16(offset + 18, arch == .arm64 ? 62 : 183, .little);
            }
            final library = Archive.decode(bytes);
            expect(
              linker.linkSharedLibrary([
                .object(root),
                .archive(library),
              ], name: 'isolated'),
              expected,
            );
            expect(
              () => linker.linkSharedLibrary([
                .object(needsUnused),
                .archive(library),
              ], name: 'isolated'),
              corrupt ? throwsFormatException : throwsUnsupportedError,
            );
          }
          for (final invalid in [
            defines({'dep': 42, 'root': 7}),
            defines({'dep': 42}, ['absent']),
          ]) {
            expect(
              () => linker.linkSharedLibrary([
                .object(root),
                .archive(archive([invalid])),
              ], name: 'invalid'),
              throwsArgumentError,
            );
          }
          final table = os == .macos ? 80 : 68;
          final data = ByteData.sublistView(encoded);
          final first = data.getUint32(
            table + (os == .macos ? 8 : 4),
            os == .macos ? .little : .big,
          );
          data.setUint32(
            table + (os == .macos ? 16 : 8),
            first,
            os == .macos ? .little : .big,
          );
          final stale = Archive.decode(encoded);
          for (final imports in [
            ['unused'],
            ['dep', 'unused'],
          ]) {
            expect(
              () => linker.linkSharedLibrary([
                .object(defines({'root': 0}, imports)),
                .archive(stale),
              ], name: 'stale'),
              throwsFormatException,
            );
          }
        },
      );
    }
  }
}
