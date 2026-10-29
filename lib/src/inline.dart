import 'ir.dart';
import 'ssa.dart';

SsaBlock? _inlineBody(SsaFunction function, FunctionInfo info) {
  if (info.typeScope.isNotEmpty ||
      ((info.contract?.flags ?? 0) & (contractAllocate | contractMayGc)) != 0)
    return null;
  var body = function.blocks[0];
  if (function.blocks.length == 2 &&
      body.instructions.isEmpty &&
      body.end.kind == 1 &&
      body.end.first.target == 1 &&
      body.end.first.arguments.isEmpty) {
    body = function.blocks[1];
  } else if (function.blocks.length != 1) {
    return null;
  }
  if (body.parameters.isNotEmpty ||
      body.end.kind != 3 ||
      function.valueTypes[body.end.value] != function.result ||
      body.instructions.length > 12)
    return null;
  // Every operation must be safe to duplicate or discard. Argument evaluation
  // remains in the caller.
  for (final instruction in body.instructions) {
    if (instruction.effects != 0) return null;
  }
  return body;
}

List<bool> inlinePureCalls(List<SsaFunction> program) {
  // Freeze candidates before rewriting callers. Candidates have no calls, so
  // bodies cannot grow during this pass, even in a recursive call graph.
  final bodies = <SsaBlock?>[
    for (var i = 0; i < program.length; i++)
      _inlineBody(program[i], functions[i]),
  ];
  final changed = List<bool>.filled(program.length, false);
  for (var f = 0; f < program.length; f++) {
    final function = program[f];
    var budget = 64;
    final aliases = <int>[];
    for (final block in function.blocks) {
      List<SsaInstruction>? instructions;
      for (var index = 0; index < block.instructions.length; index++) {
        final call = block.instructions[index];
        final body = call.op == opCall ? bodies[call.target] : null;
        var eligible = body != null && body.instructions.length <= budget;
        if (eligible) {
          final callee = program[call.target];
          for (var i = 0; i < call.inputs.length; i++) {
            if (function.valueTypes[call.inputs[i]] !=
                callee.valueTypes[callee.arguments[i]])
              eligible = false;
          }
        }
        if (!eligible || body == null) {
          instructions?.add(call);
          continue;
        }
        instructions ??= block.instructions.sublist(0, index);
        changed[f] = true;
        if (call.value < 0) continue;
        if (aliases.isEmpty) {
          for (var i = 0; i < function.valueTypes.length; i++) aliases.add(i);
        }
        final callee = program[call.target];
        final values = List<int>.filled(callee.valueTypes.length, -1);
        for (var i = 0; i < call.inputs.length; i++)
          values[callee.arguments[i]] = resolveValue(aliases, call.inputs[i]);
        for (final instruction in body.instructions) {
          if (instruction.value < 0) continue;
          final value = function.valueTypes.length;
          function.valueTypes.add(instruction.resultType);
          aliases.add(value);
          values[instruction.value] = value;
          instructions.add(
            SsaInstruction(
              instruction.op,
              value,
              instruction.target,
              <int>[for (final input in instruction.inputs) values[input]],
              instruction.effects,
              instruction.resultType,
            ),
          );
        }
        aliases[call.value] = values[body.end.value];
        budget -= body.instructions.length;
      }
      if (instructions != null) block.instructions = instructions;
    }
    if (aliases.isEmpty) continue;
    for (final block in function.blocks) {
      for (final instruction in block.instructions)
        resolveValues(aliases, instruction.inputs);
      final end = block.end;
      if (end.value >= 0) end.value = resolveValue(aliases, end.value);
      if (end.hasFirst) resolveValues(aliases, end.first.arguments);
      if (end.hasSecond) resolveValues(aliases, end.second.arguments);
    }
  }
  return changed;
}
