import 'dart:typed_data';

import 'block.dart';
import 'value.dart';

/// A function body; the first block is its entry.
///
/// One that [checksStack] calls `.stackOverflow`, which throws, instead of
/// running where the stack is used up.
final class LirFunction(
  final String name,
  final LirSignature signature,
  Iterable<LirBlock> blocks, {
  final bool checksStack = false,
}) {
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

/// Symbols that emitted code defines: where it starts, and what is stored
/// about references on the stack and about edges for throws. Only the runtime
/// uses them.
const textSymbol = '.text', stackMapSymbol = '.stackMaps';
const handlerSymbol = '.handlers';

/// Where calls are in the source, for traces of the stack.
const placesSymbol = '.places';

/// Functions that code calls for allocations, throws and overflows.
const allocateSymbol = '.allocate', throwSymbol = '.throw';
const stackOverflowSymbol = '.stackOverflow';

/// A static holding the lowest address that the stack may reach.
const stackLimitSymbol = '.stackLimit';

/// A function that calls the function of C whose call a block describes, given
/// the address of that. An external one called so is part of emitted code.
const callNativeSymbol = '.callNative';

/// Functions of C, one after the other, each of which calls
/// [callbackEntrySymbol] with its number, the address of the block of the call,
/// and that of what is passed on the stack. They are part of emitted code where
/// there is such a function.
const callbacksSymbol = '.callbacks', callbackEntrySymbol = '.callbackEntry';

/// Data that emitted code keeps the frame of the innermost such call in.
const nativeFrameSymbol = '.nativeFrame';

/// An object that exists from the start and is never collected.
///
/// [references] gives the objects that [bytes], which are zero there, refer to.
final class LirStatic(
  final String name,
  List<int> bytes, {
  Map<int, String> references = const {},
  final bool writable = false,
}) {
  final Uint8List bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final Map<int, String> references = .unmodifiable(references);
}

/// Constant 32-bit words, each the distance from the table to a function.
final class LirTable(final String name, Iterable<String> functions) {
  /// The functions' symbols, in order.
  final List<String> functions = .unmodifiable(functions);
}

/// A closed set of functions, external functions and data.
final class LirModule({
  Iterable<LirFunction> functions = const [],
  Iterable<LirExternal> externals = const [],
  Iterable<LirData> data = const [],
  Iterable<LirTable> tables = const [],
  Iterable<LirStatic> statics = const [],

  /// Functions of C by their names, and what does their work, which takes the
  /// addresses of the block of the call and of what is passed on the stack.
  final Map<String, String> exports = const {},
}) {
  final List<LirStatic> statics = .unmodifiable(statics);
  final List<LirTable> tables = .unmodifiable(tables);
  final List<LirFunction> functions = .unmodifiable(functions);
  final List<LirExternal> externals = .unmodifiable(externals);
  final List<LirData> data = .unmodifiable(data);

  /// Signatures of everything callable by name.
  late final Map<String, LirSignature> signatures = .unmodifiable({
    for (final external in externals) external.name: external.signature,
    for (final function in functions) function.name: function.signature,
  });
}
