import 'dart:typed_data';

import 'block.dart';
import 'value.dart';

/// A function body; the first block is its entry.
final class LirFunction(
  final String name,
  final LirSignature signature,
  Iterable<LirBlock> blocks,
) {
  final List<LirBlock> blocks = .unmodifiable(blocks);
  LirBlock get entry => blocks.first;
}

/// A function supplied from outside this module.
final class LirExternal(final String name, final LirSignature signature);

/// Initialized native bytes, never traced by the collector.
final class LirData(
  final String name,
  List<int> bytes, {
  final bool writable = false,
}) {
  final Uint8List bytes = Uint8List.fromList(bytes).asUnmodifiableView();
}

/// A closed set of functions, external functions and data.
final class LirModule({
  Iterable<LirFunction> functions = const [],
  Iterable<LirExternal> externals = const [],
  Iterable<LirData> data = const [],
}) {
  final List<LirFunction> functions = .unmodifiable(functions);
  final List<LirExternal> externals = .unmodifiable(externals);
  final List<LirData> data = .unmodifiable(data);

  /// Signatures of everything callable by name.
  late final Map<String, LirSignature> signatures = .unmodifiable({
    for (final external in externals) external.name: external.signature,
    for (final function in functions) function.name: function.signature,
  });
}
