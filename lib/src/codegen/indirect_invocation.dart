import 'package:dartc/ir.dart';

/// Machine wiring for a Dart call whose typed entry already belongs to the IR.
///
/// [signature] describes the entry's explicit values, including its environment.
/// Argument binding, checks and conversion algorithms belong to that entry;
/// this node only selects an address and uses the ordinary Dart completion ABI.
final class IndirectInvocation(
  final Instruction origin,
  final Value address,
  Iterable<Value> arguments,
  final FunctionType signature,
  final ExecutionSignature execution,
) extends Value {
  final List<Value> arguments = .unmodifiable(arguments);

  this : super(origin.type) {
    if (address.type != ValueType.integer ||
        signature.typeParameters.isNotEmpty ||
        signature.optionalPositional != 0 ||
        signature.named.isNotEmpty ||
        signature.parameters.length != this.arguments.length ||
        execution.parameters.length != this.arguments.length) {
      throw ArgumentError('Expected a complete indirect Dart entry signature.');
    }
  }

  Iterable<Value> get inputs => [address, ...arguments];
}
