import 'abi.dart';
import 'ir.dart';
import 'ssa.dart';

void _reachFunction(List<int> reachable, List<int> work, int target) {
  if (reachable[target] == 0) {
    reachable[target] = 1;
    work.add(target);
  }
}

List<int> reachableFunctions(List<SsaFunction> source) {
  List<int> reachable = <int>[];
  List<int> work = <int>[];
  List<int> allocated = <int>[];
  List<int> classes = <int>[];
  bool indirect = false;
  var i = 0;
  while (i < source.length) {
    reachable.add(0);
    i = i + 1;
  }
  i = 0;
  while (i < classSizes.length) {
    allocated.add(0);
    i++;
  }
  if (imageKind == 0) {
    _reachFunction(reachable, work, 0);
    var main = abiFunction('main', entrySource);
    _reachFunction(reachable, work, main);
    if (functions[main].parameters > 0) {
      _reachFunction(reachable, work, runtimeFunction(bArguments));
    }
  } else {
    i = 0;
    while (i < exportFunctions.length) {
      _reachFunction(reachable, work, exportFunctions[i]);
      i = i + 1;
    }
  }
  var cursor = 0;
  while (cursor < work.length) {
    var function = source[work[cursor]];
    var b = 0;
    while (b < function.blocks.length) {
      var instructions = function.blocks[b].instructions;
      i = 0;
      while (i < instructions.length) {
        var instruction = instructions[i];
        if (instruction.op == opCall) {
          _reachFunction(reachable, work, instruction.target);
        } else if (instruction.op == opDescriptor) {
          var owner = instruction.target;
          if (allocated[owner] == 0) {
            allocated[owner] = 1;
            classes.add(owner);
            if (indirect && classToStringFunctions[owner] >= 0) {
              _reachFunction(reachable, work, classToStringFunctions[owner]);
            }
          }
        } else if (instruction.op == opBuiltin &&
            instruction.target == bNativeCall1 &&
            !indirect) {
          indirect = true;
          var c = 0;
          while (c < classes.length) {
            var method = classToStringFunctions[classes[c]];
            if (method >= 0) _reachFunction(reachable, work, method);
            c++;
          }
        } else if (instruction.op == opBuiltin &&
            instruction.target < bNativeLoad64 &&
            instruction.target != bBoxRef) {
          _reachFunction(reachable, work, runtimeFunction(instruction.target));
        }
        i = i + 1;
      }
      b = b + 1;
    }
    cursor = cursor + 1;
  }
  return reachable;
}
