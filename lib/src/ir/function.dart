import 'block.dart';
import 'format.dart';
import 'signature.dart';
import 'value.dart';
import 'verify.dart';

/// A verified SSA control-flow graph for one function.
final class IrFunction(
  /// The declaration that callers reference.
  final FunctionTarget target,
  Iterable<Block> blocks, {
  Map<int, Constant> defaults = const {},
}) {
  /// The reachable blocks in the supplied order, starting with [entry].
  final List<Block> blocks = .unmodifiable(blocks);

  /// Default values indexed by explicit parameter slot, excluding the receiver.
  final Map<int, Constant> defaults = .unmodifiable(defaults);

  /// The block whose parameters receive the function arguments.
  Block get entry => blocks.first;

  /// Verifies the graph rooted at the first of [blocks].
  ///
  /// Throws [ArgumentError] when the entry parameters differ from the signature.
  /// Throws [StateError] for an empty or malformed graph. Every block must be
  /// sealed and reachable, and each SSA definition must dominate its uses.
  /// Each return must supply a compatible value; a bare return supplies `null`.
  this {
    final optional = target.optionalSlots;
    final offset = target.kind.hasReceiver ? 1 : 0;
    if (target.isAbstract ||
        optional.length != this.defaults.length ||
        optional.any(
          (slot) =>
              !this.defaults.containsKey(slot) ||
              !target.parameterTypes[slot + offset].accepts(
                this.defaults[slot]!.type,
              ),
        )) {
      throw ArgumentError('Invalid body or defaults for ${target.name}.');
    }
    verifyFunction(target, this.blocks);
  }

  /// Writes the typed blocks, instructions and outgoing edges to [output].
  void writeTo(StringSink output) => writeFunction(output, target, blocks);
}
