import 'machine.dart';

// Each set packs 64 values per int. Enumerate with unsigned shifts so bit 63
// participates in liveness just like the other bits.
class LivenessBlock {
  int start;
  int end;
  List<int> uses;
  List<int> definitions;
  List<int> liveIn;
  List<int> liveOut;

  LivenessBlock(
    this.start,
    this.end,
    this.uses,
    this.definitions,
    this.liveIn,
    this.liveOut,
  );
}

void _define(LivenessBlock block, int value) {
  final int word = value ~/ 64;
  block.definitions[word] = block.definitions[word] | (1 << (value & 63));
}

void _use(LivenessBlock block, int value) {
  final int word = value ~/ 64;
  final int bit = 1 << (value & 63);
  if ((block.definitions[word] & bit) == 0) {
    block.uses[word] = block.uses[word] | bit;
  }
}

List<LivenessBlock> machineLiveness(MachineFunction function) {
  final int words = (function.reps.length + 63) ~/ 64;
  final List<LivenessBlock> blocks = <LivenessBlock>[];
  int position = 0;
  int b = 0;
  while (b < function.blocks.length) {
    final MachineBlock source = function.blocks[b];
    final int end = position + source.instructions.length * 2 + 1;
    final LivenessBlock block = LivenessBlock(
      position,
      end,
      List<int>.filled(words, 0),
      List<int>.filled(words, 0),
      List<int>.filled(words, 0),
      List<int>.filled(words, 0),
    );
    int i = 0;
    if (b == 0) {
      while (i < function.arguments.length) {
        _define(block, function.arguments[i]);
        i = i + 1;
      }
    }
    i = 0;
    while (i < source.parameters.length) {
      _define(block, source.parameters[i]);
      i = i + 1;
    }
    i = 0;
    while (i < source.instructions.length) {
      final MachineInstruction instruction = source.instructions[i];
      int input = 0;
      while (input < instruction.inputs.length) {
        _use(block, instruction.inputs[input]);
        input = input + 1;
      }
      if (instruction.output >= 0) _define(block, instruction.output);
      i = i + 1;
    }
    final MachineTerminator term = source.end;
    if (term.value >= 0) _use(block, term.value);
    i = 0;
    while (i < term.first.arguments.length) {
      _use(block, term.first.arguments[i]);
      i = i + 1;
    }
    i = 0;
    while (i < term.second.arguments.length) {
      _use(block, term.second.arguments[i]);
      i = i + 1;
    }
    blocks.add(block);
    position = end + 1;
    b = b + 1;
  }
  bool changed = true;
  while (changed) {
    changed = false;
    b = blocks.length;
    while (b > 0) {
      b = b - 1;
      final LivenessBlock block = blocks[b];
      final MachineTerminator term = function.blocks[b].end;
      int word = 0;
      while (word < words) {
        int out = 0;
        if (term.first.target >= 0) {
          out = out | blocks[term.first.target].liveIn[word];
        }
        if (term.second.target >= 0) {
          out = out | blocks[term.second.target].liveIn[word];
        }
        final int inside = block.uses[word] | (out & ~block.definitions[word]);
        if (block.liveIn[word] != inside || block.liveOut[word] != out) {
          block.liveIn[word] = inside;
          block.liveOut[word] = out;
          changed = true;
        }
        word = word + 1;
      }
    }
  }
  return blocks;
}
