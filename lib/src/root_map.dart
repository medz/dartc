import 'allocate.dart';
import 'host.dart';
import 'layout.dart';
import 'machine.dart';

class CallRootMap {
  int block;
  int instruction;
  List<int> offsets;
  List<int> kinds;
  int returnOffset = -1;
  bool boundary = false;

  CallRootMap(this.block, this.instruction, this.offsets, this.kinds);
}

List<CallRootMap> emittedRootMaps = <CallRootMap>[];

void _rootUse(List<int> live, int value) {
  final word = value ~/ 32;
  live[word] = live[word] | (1 << (value & 31));
}

Never _rootMapError(String message) {
  print('dartc root map: ' + message);
  hostExit(1);
}

CallRootMap _callRootMap(
  MachineFunction function,
  List<int> live,
  List<int> slots,
  int block,
  int instruction,
) {
  final result = CallRootMap(block, instruction, <int>[], <int>[]);
  var word = 0;
  while (word < live.length) {
    var bits = live[word];
    var bit = 0;
    while (bits != 0) {
      if ((bits & 1) != 0) {
        final value = word * 32 + bit;
        final rep = function.reps[value];
        if (rep == rRef || rep == rTagged) {
          final location = function.allocation.locations[value];
          if (location >= 0) _rootMapError('live root is not spilled');
          final slot = -1 - location;
          var kind = storageRef;
          if (rep == rTagged) kind = storageTagged;
          if (slots[slot] != 0 && slots[slot] != kind) {
            _rootMapError('incompatible live roots share a spill slot');
          }
          if (slots[slot] == 0) {
            slots[slot] = kind;
            result.offsets.add(location * 8);
            result.kinds.add(kind);
          }
        }
      }
      bits = bits >>> 1;
      bit++;
    }
    word++;
  }
  var i = 0;
  while (i < result.offsets.length) {
    slots[-1 - result.offsets[i] ~/ 8] = 0;
    i++;
  }
  return result;
}

List<CallRootMap> buildCallRootMaps(MachineFunction function) {
  final blocks = allocateLiveness(function);
  final slots = List<int>.filled(function.allocation.spillSlots, 0);
  final result = <CallRootMap>[];
  var b = 0;
  while (b < function.blocks.length) {
    final block = function.blocks[b];
    final live = blocks[b].liveOut.sublist(0);
    final end = block.end;
    if (end.value >= 0) _rootUse(live, end.value);
    var i = 0;
    while (i < end.first.arguments.length) {
      _rootUse(live, end.first.arguments[i]);
      i++;
    }
    i = 0;
    while (i < end.second.arguments.length) {
      _rootUse(live, end.second.arguments[i]);
      i++;
    }
    var first = result.length;
    i = block.instructions.length;
    while (i > 0) {
      i--;
      final instruction = block.instructions[i];
      if (instruction.output >= 0) {
        final value = instruction.output;
        final word = value ~/ 32;
        live[word] = live[word] & ~(1 << (value & 31));
      }
      var input = 0;
      while (input < instruction.inputs.length) {
        _rootUse(live, instruction.inputs[input]);
        input++;
      }
      if (instruction.op == mCall || instruction.op == mCallIndirect) {
        result.add(_callRootMap(function, live, slots, b, i));
      }
    }
    var last = result.length - 1;
    while (first < last) {
      final saved = result[first];
      result[first] = result[last];
      result[last] = saved;
      first++;
      last--;
    }
    b++;
  }
  return result;
}
