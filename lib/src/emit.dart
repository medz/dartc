import 'arm64_emit.dart';
import 'x64_emit.dart';
import 'target.dart';
import 'code.dart';
import 'frame.dart';
import 'layout.dart';
import 'machine.dart';
import 'root_map.dart';

int emitMetadataFeatures(List<MachineFunction> program) {
  var features = 0;
  var f = 0;
  while (f < program.length) {
    var function = program[f];
    if (!function.reachable) {
      f++;
      continue;
    }
    var b = 0;
    while (b < function.blocks.length) {
      final end = function.blocks[b].end;
      if (end.kind == 5 || end.kind == 6)
        features |= metadataFrames | metadataHandlers;
      var instructions = function.blocks[b].instructions;
      var i = 0;
      while (i < instructions.length) {
        var instruction = instructions[i];
        if (instruction.op == mAddress && instruction.extra == 3)
          features |= instruction.target;
        i++;
      }
      b++;
    }
    f++;
  }
  return features;
}

void generateCode(List<MachineFunction> program) {
  emittedRootMaps.clear();
  emittedFrames.clear();
  emittedHandlers.clear();
  codeWords.clear();
  codeSize = 0;
  codeAddresses.clear();
  codeCalls.clear();
  functionOffsets.clear();
  for (var i = 0; i < program.length; i++) functionOffsets.add(0);
  final features = emitMetadataFeatures(program);
  if (targetX64)
    generateX64(program, features);
  else
    generateArm64(program, features);
}
