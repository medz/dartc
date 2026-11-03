import 'block.dart';
import 'format.dart';
import 'signature.dart';
import 'verify.dart';

/// A verified SSA graph. The first block receives the function arguments.
final class IrFunction {
  final FunctionTarget target;
  final List<Block> blocks;
  Block get entry => blocks.first;

  /// All blocks must be finished and reachable. Every SSA use must be dominated
  /// by its definition, and each edge must supply the target's parameter types.
  IrFunction(this.target, Iterable<Block> blocks)
    : blocks = List.unmodifiable(blocks) {
    verifyFunction(target, this.blocks);
  }

  /// Writes the typed blocks and their successors in a human-readable form.
  void writeTo(StringSink output) => writeFunction(output, target, blocks);
}
