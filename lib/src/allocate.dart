import 'target.dart';
import 'machine.dart';

class RegisterBlock {
  int start;
  int end;
  List<int> uses;
  List<int> definitions;
  List<int> liveIn;
  List<int> liveOut;

  RegisterBlock(
    this.start,
    this.end,
    this.uses,
    this.definitions,
    this.liveIn,
    this.liveOut,
  );
}

void allocateDefine(RegisterBlock block, int value) {
  final int word = value ~/ 32;
  block.definitions[word] = block.definitions[word] | (1 << (value & 31));
}

void allocateUse(RegisterBlock block, int value) {
  final int word = value ~/ 32;
  final int bit = 1 << (value & 31);
  if ((block.definitions[word] & bit) == 0) {
    block.uses[word] = block.uses[word] | bit;
  }
}

List<RegisterBlock> allocateLiveness(MachineFunction function) {
  final int words = (function.reps.length + 31) ~/ 32;
  final List<RegisterBlock> blocks = <RegisterBlock>[];
  int position = 0;
  int b = 0;
  while (b < function.blocks.length) {
    final MachineBlock source = function.blocks[b];
    final int end = position + source.instructions.length * 2 + 1;
    final RegisterBlock block = RegisterBlock(
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
        allocateDefine(block, function.arguments[i]);
        i = i + 1;
      }
    }
    i = 0;
    while (i < source.parameters.length) {
      allocateDefine(block, source.parameters[i]);
      i = i + 1;
    }
    i = 0;
    while (i < source.instructions.length) {
      final MachineInstruction instruction = source.instructions[i];
      int input = 0;
      while (input < instruction.inputs.length) {
        allocateUse(block, instruction.inputs[input]);
        input = input + 1;
      }
      if (instruction.output >= 0) allocateDefine(block, instruction.output);
      i = i + 1;
    }
    final MachineTerminator term = source.end;
    if (term.value >= 0) allocateUse(block, term.value);
    i = 0;
    while (i < term.first.arguments.length) {
      allocateUse(block, term.first.arguments[i]);
      i = i + 1;
    }
    i = 0;
    while (i < term.second.arguments.length) {
      allocateUse(block, term.second.arguments[i]);
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
      final RegisterBlock block = blocks[b];
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
        int inside = block.uses[word] | (out & ~block.definitions[word]);
        inside = inside & 0xffffffff;
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

void allocateTouch(List<int> starts, List<int> ends, int value, int position) {
  if (starts[value] < 0 || position < starts[value]) starts[value] = position;
  if (position > ends[value]) ends[value] = position;
}

void allocateLiveIntervals(
  List<int> live,
  int position,
  List<int> starts,
  List<int> ends,
) {
  int word = 0;
  while (word < live.length) {
    int bits = live[word];
    int bit = 0;
    while (bits != 0) {
      if ((bits & 1) != 0) {
        allocateTouch(starts, ends, word * 32 + bit, position);
      }
      bits = bits >>> 1;
      bit = bit + 1;
    }
    word = word + 1;
  }
}

void allocateIntervals(
  MachineFunction function,
  List<RegisterBlock> blocks,
  List<int> starts,
  List<int> ends,
) {
  int i = 0;
  while (i < function.arguments.length) {
    allocateTouch(starts, ends, function.arguments[i], 0);
    i = i + 1;
  }
  int b = 0;
  while (b < blocks.length) {
    final RegisterBlock block = blocks[b];
    final MachineBlock source = function.blocks[b];
    allocateLiveIntervals(block.liveIn, block.start, starts, ends);
    allocateLiveIntervals(block.liveOut, block.end, starts, ends);
    i = 0;
    while (i < source.parameters.length) {
      allocateTouch(starts, ends, source.parameters[i], block.start);
      i = i + 1;
    }
    int position = block.start + 1;
    i = 0;
    while (i < source.instructions.length) {
      final MachineInstruction instruction = source.instructions[i];
      int input = 0;
      while (input < instruction.inputs.length) {
        allocateTouch(starts, ends, instruction.inputs[input], position);
        input = input + 1;
      }
      // Inputs precede the output, allowing a dead input's location to be reused.
      if (instruction.output >= 0) {
        allocateTouch(starts, ends, instruction.output, position + 1);
      }
      position = position + 2;
      i = i + 1;
    }
    final MachineTerminator term = source.end;
    if (term.value >= 0) allocateTouch(starts, ends, term.value, block.end);
    i = 0;
    while (i < term.first.arguments.length) {
      allocateTouch(starts, ends, term.first.arguments[i], block.end);
      i = i + 1;
    }
    i = 0;
    while (i < term.second.arguments.length) {
      allocateTouch(starts, ends, term.second.arguments[i], block.end);
      i = i + 1;
    }
    b = b + 1;
  }
}

bool allocateEarlier(int left, int right, List<int> keys) {
  return keys[left] < keys[right] || keys[left] == keys[right] && left < right;
}

void allocateHeapPush(List<int> heap, int value, List<int> keys) {
  heap.add(value);
  int position = heap.length - 1;
  while (position > 0) {
    final int parent = (position - 1) ~/ 2;
    if (!allocateEarlier(value, heap[parent], keys)) break;
    heap[position] = heap[parent];
    position = parent;
  }
  heap[position] = value;
}

int allocateHeapPop(List<int> heap, List<int> keys) {
  final int result = heap[0];
  final int last = heap.removeLast();
  if (heap.length != 0) {
    int position = 0;
    int child = 1;
    while (child < heap.length) {
      if (child + 1 < heap.length &&
          allocateEarlier(heap[child + 1], heap[child], keys)) {
        child = child + 1;
      }
      if (!allocateEarlier(heap[child], last, keys)) break;
      heap[position] = heap[child];
      position = child;
      child = position * 2 + 1;
    }
    heap[position] = last;
  }
  return result;
}

List<int> allocateOrder(List<int> starts) {
  final List<int> heap = <int>[];
  int value = 0;
  while (value < starts.length) {
    if (starts[value] >= 0) allocateHeapPush(heap, value, starts);
    value = value + 1;
  }
  final List<int> order = <int>[];
  while (heap.length != 0) order.add(allocateHeapPop(heap, starts));
  return order;
}

void allocatePhysicalRegisters(
  MachineFunction function,
  List<int> order,
  List<int> starts,
  List<int> ends,
  List<int> locations,
) {
  final registers = targetRegisters;
  final List<int> owners = List<int>.filled(registers.length, -1);
  int i = 0;
  while (i < order.length) {
    final int value = order[i];
    final int rep = function.reps[value];
    if (rep == rI64 || rep == rI1 || rep == rAddr || rep == rF64Bits) {
      int register = 0;
      int available = -1;
      int farthest = 0;
      while (register < owners.length) {
        int previous = owners[register];
        if (previous >= 0 && ends[previous] < starts[value]) {
          owners[register] = -1;
          previous = -1;
        }
        if (previous < 0) {
          if (available < 0) available = register;
        } else if (owners[farthest] < 0 ||
            ends[previous] > ends[owners[farthest]]) {
          farthest = register;
        }
        register = register + 1;
      }
      if (available >= 0) {
        locations[value] = registers[available];
        owners[available] = value;
      } else if (ends[owners[farthest]] > ends[value]) {
        locations[owners[farthest]] = -1;
        locations[value] = registers[farthest];
        owners[farthest] = value;
      }
    }
    i = i + 1;
  }
}

int allocateSpillSlots(
  List<int> order,
  List<int> starts,
  List<int> ends,
  List<int> locations,
) {
  final List<int> active = <int>[];
  final List<int> free = <int>[];
  int count = 0;
  int i = 0;
  while (i < order.length) {
    final int value = order[i];
    if (locations[value] < 0) {
      while (active.length != 0 && ends[active[0]] < starts[value]) {
        final int previous = allocateHeapPop(active, ends);
        free.add(-1 - locations[previous]);
      }
      int slot = count;
      if (free.length != 0) {
        slot = free.removeLast();
      } else {
        count = count + 1;
      }
      locations[value] = -1 - slot;
      allocateHeapPush(active, value, ends);
    }
    i = i + 1;
  }
  return count;
}

void allocateFunction(MachineFunction function) {
  final List<RegisterBlock> blocks = allocateLiveness(function);
  final List<int> starts = List<int>.filled(function.reps.length, -1);
  final List<int> ends = List<int>.filled(function.reps.length, -1);
  allocateIntervals(function, blocks, starts, ends);
  final List<int> order = allocateOrder(starts);
  final List<int> locations = List<int>.filled(function.reps.length, -1);
  allocatePhysicalRegisters(function, order, starts, ends, locations);
  final int spills = allocateSpillSlots(order, starts, ends, locations);
  var used = 0;
  for (final location in locations) {
    if (location >= 0) used |= 1 << location;
  }
  final saved = <int>[
    for (final register in targetRegisters)
      if ((used & (1 << register)) != 0) register,
  ];
  function.allocation = RegisterAllocation(locations, spills, saved);
}

void allocateRegisters(List<MachineFunction> program) {
  int i = 0;
  while (i < program.length) {
    if (program[i].reachable) allocateFunction(program[i]);
    i = i + 1;
  }
}
