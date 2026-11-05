import 'block.dart';
import 'core_types.dart';
import 'format.dart';
import 'signature.dart';
import 'type.dart';
import 'value.dart';
import 'verify.dart';

/// A verified SSA control-flow graph for one callable body.
///
/// Generator graphs explicitly represent suspension; a backend must preserve
/// their activations or lower them to state machines before ordinary codegen.
final class IrFunction(
  /// The declaration that callers reference.
  final FunctionTarget target,
  Iterable<Block> blocks, {
  Map<int, Constant> defaults = const {},

  /// Whether this graph returns directly or suspends an iterator activation.
  final FunctionBodyKind bodyKind = .synchronous,

  /// The element type of a generator body, absent for an ordinary function.
  final ValueType? yieldType,
}) {
  /// The reachable blocks in the supplied order, starting with [entry].
  final List<Block> blocks = .unmodifiable(blocks);

  /// Default values indexed by explicit parameter slot, excluding the receiver.
  final Map<int, Constant> defaults = .unmodifiable(defaults);

  /// The local bodies that this graph can instantiate.
  late final Set<FunctionTarget> closures;

  /// The global declarations directly read or written by this graph.
  late final Set<GlobalVariable> globals;

  /// The block whose parameters receive the function arguments.
  Block get entry => blocks.first;

  /// Verifies the graph rooted at the first of [blocks].
  ///
  /// Throws [ArgumentError] when the entry parameters differ from the signature.
  /// Throws [StateError] for an empty or malformed graph. Every block must be
  /// sealed and reachable, and each SSA definition must dominate its uses.
  /// Ordinary returns must match the callable result. Generator returns complete
  /// iteration and supply only `null`; yields must match [yieldType].
  this {
    if ((bodyKind == .syncGenerator) != (yieldType != null) ||
        yieldType is CellType ||
        yieldType != null &&
            (!target.returnType.accepts(CoreTypes.iterableOf(yieldType!)) ||
                target.returnType == .voidType ||
                target.kind == .initializer ||
                target.kind == .factory ||
                target.kind == .fieldInitializer ||
                target.kind == .setter ||
                target.kind == .staticSetter)) {
      throw ArgumentError('Invalid generator body for ${target.name}.');
    }
    final optional = target.signature.optionalSlots;
    final offset = target.argumentOffset;
    if (target.isAbstract ||
        target.redirect != null ||
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
    final references = verifyFunction(
      target,
      this.blocks,
      this.defaults.values,
      yieldType: yieldType,
    );
    closures = references.closures;
    globals = references.globals;
  }

  /// Writes the typed blocks, instructions and outgoing edges to [output].
  void writeTo(StringSink output) =>
      writeFunction(output, target, blocks, yieldType: yieldType);
}
