import 'package:dartc/lir.dart';

/// A function with a single block, whose parameters match [parameters].
LirFunction function(
  String name,
  List<LirType> parameters,
  LirType? result,
  LirValue? Function(LirBlock block, List<LirParameter> parameters) build,
) {
  final block = LirBlock(parameters);
  final value = build(block, block.parameters);
  block.end(Return(value));
  return LirFunction(name, LirSignature(parameters, result), [block]);
}

/// Evaluates one operation on [arguments] of the given types.
Object? evaluate(
  List<LirType> parameters,
  LirType result,
  LirInstruction Function(List<LirParameter> p) build,
  List<Object?> arguments,
) => LirInterpreter(
  LirModule(
    functions: [
      function('f', parameters, result, (block, p) => block.add(build(p))),
    ],
  ),
).call('f', arguments);
