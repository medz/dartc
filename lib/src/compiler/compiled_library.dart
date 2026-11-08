import 'dart:io';

import 'package:dartc/artifact.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/formats.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/linker.dart';

/// Native code and declarations ready to write without retaining analyzer state.
final class CompiledLibrary(
  final ObjectModule object,
  final NativeExports exports,
  Iterable<Uri> sources,
) {
  final List<Uri> _sources = .unmodifiable(sources);

  this {
    final names = {
      for (final export in exports.functions)
        object.target.nativeSymbol(export.symbol),
    };
    if (names.length != object.symbols.where((s) => s.exported).length ||
        object.symbols.any(
          (symbol) => symbol.exported && !names.contains(symbol.name),
        )) {
      throw ArgumentError('Object symbols do not match the native exports.');
    }
  }

  /// Writes an object or library and, optionally, its C header.
  ///
  /// Each file is replaced only after its contents are ready. The two-file
  /// update is not transactional if a filesystem error occurs between renames.
  Future<void> write(
    File output, {
    OutputKind kind = .object,
    File? header,
  }) async {
    final destinations = [output, ?header];
    final protected = {
      for (final source in _sources)
        if (source.scheme == 'file') _identity(File.fromUri(source)),
    };
    final names = <String>{};
    for (final file in destinations) {
      final name = _identity(file);
      final aliasesSource =
          file.existsSync() &&
          _sources.any(
            (source) =>
                source.scheme == 'file' &&
                FileSystemEntity.identicalSync(file.path, source.toFilePath()),
          );
      if (protected.contains(name) || aliasesSource || !names.add(name)) {
        throw ArgumentError(
          'Output would overwrite an input or another output: ${file.path}',
        );
      }
    }
    final ImageFormat format = switch (object.target.operatingSystem) {
      .macos => MachO(object.target),
      .linux => Elf(object.target),
    };
    final bytes = switch (kind) {
      .object => format.encodeObject(object),
      .staticLibrary => ArchiveWriter(format).encode([object]),
      .sharedLibrary => format.encodeImage(
        Linker(format)
            .link([object], libraryName: output.uri.pathSegments.last),
      ),
    };
    await _write(output, bytes);
    if (header != null) {
      final text = StringBuffer();
      exports.writeHeader(text);
      await _write(header, SystemEncoding().encode(text.toString()));
    }
  }

  String _identity(File file) {
    if (file.existsSync()) return file.resolveSymbolicLinksSync();
    final uri = file.absolute.uri.normalizePath();
    var parent = File.fromUri(uri).parent;
    final parts = [uri.pathSegments.last];
    while (!parent.existsSync()) {
      parts.insert(0, parent.uri.pathSegments.where((s) => s.isNotEmpty).last);
      parent = parent.parent;
    }
    return Directory(parent.resolveSymbolicLinksSync()).uri
        .resolveUri(Uri(pathSegments: parts))
        .toFilePath();
  }

  Future<void> _write(File file, List<int> bytes) async {
    await file.absolute.parent.create(recursive: true);
    final work = await file.absolute.parent.createTemp('.dartc-write-');
    try {
      final staged = File.fromUri(work.uri.resolve('output'));
      await staged.writeAsBytes(bytes);
      await staged.rename(file.absolute.path);
    } finally {
      await work.delete(recursive: true);
    }
  }
}
