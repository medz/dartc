import 'target.dart';
import 'machine.dart';
import 'liveness.dart';
import 'host.dart';

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

List<int> allocateIntervals(
  MachineFunction function,
  List<LivenessBlock> blocks,
  List<int> starts,
  List<int> ends,
) {
  final clobbers = <int>[];
  int i = 0;
  while (i < function.arguments.length) {
    allocateTouch(starts, ends, function.arguments[i], 0);
    i = i + 1;
  }
  int b = 0;
  while (b < blocks.length) {
    final LivenessBlock block = blocks[b];
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
      if (machineClobbersCallerSaved(instruction.op)) clobbers.add(position);
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
  return clobbers;
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
  List<int> clobbers,
) {
  final generalRegisters = targetRegisters;
  final floatingRegisters = targetFloatRegisters;
  final generalOwners = List<int>.filled(generalRegisters.length, -1);
  final floatingOwners = List<int>.filled(floatingRegisters.length, -1);
  var nextClobber = 0;
  int i = 0;
  while (i < order.length) {
    final int value = order[i];
    final int rep = function.reps[value];
    while (nextClobber < clobbers.length &&
        clobbers[nextClobber] < starts[value])
      nextClobber++;
    if (rep == rI64 || rep == rI1 || rep == rAddr || rep == rF64Bits) {
      final floating =
          rep == rF64Bits &&
          floatingRegisters.isNotEmpty &&
          (nextClobber == clobbers.length ||
              ends[value] <= clobbers[nextClobber]);
      final registers = floating ? floatingRegisters : generalRegisters;
      final owners = floating ? floatingOwners : generalOwners;
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
  final List<LivenessBlock> blocks = machineLiveness(function);
  final List<int> starts = List<int>.filled(function.reps.length, -1);
  final List<int> ends = List<int>.filled(function.reps.length, -1);
  final clobbers = allocateIntervals(function, blocks, starts, ends);
  final List<int> order = allocateOrder(starts);
  final List<int> locations = List<int>.filled(function.reps.length, -1);
  allocatePhysicalRegisters(function, order, starts, ends, locations, clobbers);
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
  verifyAllocation(function, blocks);
}

Never allocationError(String message) {
  print('dartc allocation: ' + message);
  hostExit(1);
}

// Check actual live values backwards through each block, independently of the
// interval ordering and eviction decisions used by the allocator.
void verifyAllocation(MachineFunction function, List<LivenessBlock> blocks) {
  final allocation = function.allocation;
  final locations = allocation.locations;
  var general = 0;
  for (final register in targetRegisters) general |= 1 << register;
  var floating = 0;
  for (final register in targetFloatRegisters) floating |= 1 << register;
  var saved = 0;
  for (final register in allocation.savedRegisters) {
    if (register < 0 ||
        register >= floatRegisterBase ||
        (general & (1 << register)) == 0 ||
        (saved & (1 << register)) != 0)
      allocationError('invalid saved register');
    saved |= 1 << register;
  }
  final owners = List<int>.filled(64 + allocation.spillSlots, -1);
  int slot(int value) {
    if (value < 0 || value >= locations.length)
      allocationError('invalid value');
    final location = locations[value];
    if (location < 0) {
      if (-1 - location >= allocation.spillSlots)
        allocationError('spill slot out of range');
      return 63 - location;
    }
    final rep = function.reps[value];
    if (rep == rRef || rep == rTagged)
      allocationError('managed root in register');
    if (location >= 64 || ((general | floating) & (1 << location)) == 0)
      allocationError('unavailable register');
    if (location >= floatRegisterBase) {
      if (rep != rF64Bits) allocationError('floating register representation');
    } else if ((saved & (1 << location)) == 0) {
      allocationError('missing saved register');
    }
    return location;
  }

  void use(int value) {
    final location = slot(value);
    if (owners[location] >= 0 && owners[location] != value)
      allocationError('overlapping live values');
    owners[location] = value;
  }

  void define(int value) {
    final location = slot(value);
    if (owners[location] >= 0 && owners[location] != value)
      allocationError('definition overwrites live value');
    owners[location] = -1;
  }

  for (var b = 0; b < blocks.length; b++) {
    for (var i = 0; i < owners.length; i++) owners[i] = -1;
    final live = blocks[b].liveOut;
    for (var word = 0; word < live.length; word++) {
      var bits = live[word];
      var bit = 0;
      while (bits != 0) {
        if ((bits & 1) != 0) use(word * 32 + bit);
        bits >>>= 1;
        bit++;
      }
    }
    final block = function.blocks[b];
    final end = block.end;
    if (end.value >= 0) use(end.value);
    for (final value in end.first.arguments) use(value);
    for (final value in end.second.arguments) use(value);
    for (var i = block.instructions.length - 1; i >= 0; i--) {
      final instruction = block.instructions[i];
      if (instruction.output >= 0) define(instruction.output);
      if (machineClobbersCallerSaved(instruction.op)) {
        for (final register in targetFloatRegisters) {
          if (owners[register] >= 0)
            allocationError('live floating value across clobber');
        }
      }
      for (final value in instruction.inputs) use(value);
    }
    for (final value in block.parameters) define(value);
    if (b == 0) {
      for (final value in function.arguments) define(value);
    }
  }
}

void allocateRegisters(List<MachineFunction> program) {
  int i = 0;
  while (i < program.length) {
    if (program[i].reachable) allocateFunction(program[i]);
    i = i + 1;
  }
}
