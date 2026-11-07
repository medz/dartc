import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/artifact.dart';
import 'package:dartc/formats.dart';
import 'package:dartc/target.dart';

/// Links position-independent code artifacts for an explicit target.
///
/// Inputs contain defined functions without data sections or unresolved
/// references, as required by [ObjectFile]. Linking is independent of the host.
final class Linker(final Target target) {
  /// Builds a native library, preserving an existing output if linking fails.
  Future<void> link(
    Iterable<ObjectFile> input,
    File output,
    OutputKind kind,
  ) async {
    final objects = input.toList();
    if (kind == .object ||
        objects.isEmpty ||
        objects.any((o) => o.target != target)) {
      throw ArgumentError(
        'Expected matching objects and a library output kind.',
      );
    }
    final Uint8List bytes;
    if (kind == .staticLibrary) {
      bytes = Archive.encode(objects);
    } else {
      final code = BytesBuilder(copy: false), symbols = <Symbol>[];
      final names = <String>{};
      for (final object in objects) {
        code.add(Uint8List((-code.length) & 15));
        final base = code.length;
        for (final symbol in object.symbols) {
          if (!names.add(symbol.name)) {
            throw ArgumentError('Duplicate symbol: ${symbol.name}');
          }
          symbols.add(.new(symbol.name, base + symbol.offset, symbol.size));
        }
        code.add(object.code);
      }
      final image = ObjectFile(target, code.takeBytes(), symbols);
      final name = output.uri.pathSegments.last;
      bytes = switch (target.operatingSystem) {
        .macos => MachO.shared(image, '@rpath/$name'),
        .linux => Elf.shared(image, name),
      };
    }
    await output.absolute.parent.create(recursive: true);
    final work = await output.absolute.parent.createTemp('.dartc-link-');
    try {
      final linked = File.fromUri(work.uri.resolve('output'));
      await linked.writeAsBytes(bytes);
      await linked.rename(output.absolute.path);
    } finally {
      await work.delete(recursive: true);
    }
  }
}
