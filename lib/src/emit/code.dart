import 'dart:typed_data';

import 'package:dartc/native.dart';

import 'stack_maps.dart';

/// LIR that this version cannot translate yet.
final class EmitUnsupported(final String function, final String what)
    implements Exception {
  @override
  String toString() => 'EmitUnsupported: $function: $what';
}

/// How a symbol's address enters an ARM64 instruction.
enum RelocationKind() {
  /// A 26-bit word displacement in `bl`.
  call26,

  /// A page displacement in `adrp`.
  page21,

  /// The low 12 address bits in `add`.
  pageOffset12,
}

/// An instruction at [offset] awaiting the address of [symbol].
final class Relocation(
  final int offset,
  final RelocationKind kind,
  final String symbol,
);

/// An object that exists from the start.
///
/// [references] gives the objects that its words at some offsets refer to.
final class EmittedObject(
  final Uint8List bytes,
  Map<int, String> references, {
  required final bool writable,
}) {
  final Map<int, String> references = .unmodifiable(references);
}

/// Position-independent code before its final addresses are known.
final class EmittedCode(
  final Uint8List text,

  /// The offset of each function in [text].
  Map<String, int> functions,
  Iterable<Relocation> relocations, {

  /// Functions the system supplies, by their C names.
  Iterable<String> externals = const [],

  /// Constant bytes, each aligned to 16.
  Map<String, Uint8List> data = const {},

  /// Tables of 32-bit distances from the table to each function.
  Map<String, List<String>> tables = const {},

  /// Objects and writable bytes that exist from the start, each aligned to 16.
  Map<String, EmittedObject> objects = const {},

  /// What each call keeps alive, sorted by where it returns to.
  Iterable<StackMap> stackMaps = const [],

  /// Where calls that throw continue, sorted by where they return to.
  Iterable<ThrowTarget> throwTargets = const [],

  /// The functions that others see, by what they call them.
  Map<String, String> exports = const {},

  /// What runs it.
  final Architecture architecture = .arm64,
}) {
  final Map<String, String> exports = .unmodifiable(exports);
  final List<ThrowTarget> throwTargets = .unmodifiable(throwTargets);
  final Map<String, EmittedObject> objects = .unmodifiable(objects);
  final List<StackMap> stackMaps = .unmodifiable(stackMaps);
  final Map<String, List<String>> tables = .unmodifiable(tables);
  final Map<String, Uint8List> data = .unmodifiable(data);
  final List<String> externals = .unmodifiable(externals);
  final Map<String, int> functions = .unmodifiable(functions);
  final List<Relocation> relocations = .unmodifiable(relocations);
}
