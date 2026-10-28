import 'constant_data.dart';
import 'ir.dart';
import 'layout.dart';
import 'ssa.dart';
import 'types.dart';

bool _compatible(int actual, int expected) {
  return actual == expected ||
      typeIsTagged(actual) == typeIsTagged(expected) &&
          typeIsReference(actual) == typeIsReference(expected) &&
          typeIsSubtype(actual, expected);
}

class _SsaVerifier {
  final SsaFunction function;
  final int number;
  final List<int> owners;
  final List<int> positions;
  final List<List<int>> predecessors;
  List<int> rank = const <int>[];
  List<int> entered = const <int>[];
  List<int> exited = const <int>[];
  final List<List<bool>?> withoutNormal = <List<bool>?>[];
  int block = -1;
  int position = -1;

  _SsaVerifier(
    this.function,
    this.number,
    this.owners,
    this.positions,
    this.predecessors,
  );

  Never fail(String reason) {
    ssaError(
      'verify ' +
          functions[number].name +
          ' block ' +
          block.toString() +
          ' instruction ' +
          position.toString() +
          ': ' +
          reason,
    );
  }

  void type(int id) {
    if (id < 0 || id >= dartTypes.length) fail('invalid type');
    if (typeHasSchemaHole(id) ||
        !typeParametersInScope(id, functions[number].typeScope))
      fail('uninstantiated executable type');
  }

  void value(int id) {
    if (id < 0 || id >= owners.length) fail('invalid value');
  }

  int inputType(int id) {
    value(id);
    return function.valueTypes[id];
  }

  void define(int id, int at) {
    value(id);
    if (owners[id] >= 0) fail('duplicate definition');
    owners[id] = block;
    positions[id] = at;
  }

  void definitions() {
    final info = functions[number];
    final closure = info.closureLayout;
    if (closure != null && closure.typeParameters.isNotEmpty) {
      if (info.typeParameters.isNotEmpty ||
          closure.boundReceiver ||
          closure.fieldTypes.isEmpty ||
          closure.fieldTypes[0] != listType(tObject) ||
          info.parameterTypes.isEmpty ||
          info.parameterTypes[0] != tFunction)
        fail('closure type environment layout');
      var enclosing = -1;
      for (var i = 0; i < closure.typeParameters.length; i++) {
        final parameter = closure.typeParameters[i];
        if (parameter < 0 ||
            parameter >= dartTypes.length ||
            !typeIsParameter(parameter))
          fail('closure type environment parameter');
        final declaration = typeParameterInfo(parameter);
        final owner = -declaration.owner - 1;
        if (i == 0) enclosing = owner;
        if (owner < 0 ||
            owner >= functions.length ||
            owner != enclosing ||
            functions[owner].typeParameters.length !=
                closure.typeParameters.length ||
            functions[owner].typeParameters[i] != parameter ||
            declaration.ordinal != i)
          fail('closure type environment scope');
      }
    }
    if (info.typeParameters.isNotEmpty &&
        (info.typeEnvironment < 0 ||
            info.typeEnvironment >= info.parameters ||
            info.parameterTypes[info.typeEnvironment] != listType(tObject)))
      fail('generic type environment');
    for (var i = 0; i < info.typeParameters.length; i++) {
      var parameter = info.typeParameters[i];
      if (parameter < 0 ||
          parameter >= dartTypes.length ||
          !typeIsParameter(parameter))
        fail('generic parameter type');
      var declaration = typeParameterInfo(parameter);
      if (declaration.owner != -number - 1 || declaration.ordinal != i)
        fail('generic parameter identity');
      type(declaration.bound);
    }
    type(function.result);
    if (function.result != info.result ||
        function.blocks.isEmpty ||
        function.arguments.length != info.parameters ||
        info.parameterTypes.length != info.parameters ||
        info.localTypes.length != info.locals)
      fail('function metadata');
    for (var item in function.valueTypes) type(item);
    block = 0;
    var i = 0;
    while (i < function.arguments.length) {
      final id = function.arguments[i];
      define(id, -1);
      if (function.valueTypes[id] != info.parameterTypes[i])
        fail('argument type');
      i++;
    }
    if (function.blocks[0].parameters.isNotEmpty)
      fail('entry block parameters');
    block = 0;
    while (block < function.blocks.length) {
      final body = function.blocks[block];
      if (body.localSlots.length > body.parameters.length)
        fail('local parameter prefix');
      i = 0;
      while (i < body.parameters.length) {
        define(body.parameters[i], -1);
        if (i < body.localSlots.length) {
          final slot = body.localSlots[i];
          if (slot < 0 ||
              slot >= info.locals ||
              i > 0 && body.localSlots[i - 1] >= slot)
            fail('local parameter slot');
          if (function.valueTypes[body.parameters[i]] != info.localTypes[slot])
            fail('local parameter type');
        }
        i++;
      }
      position = 0;
      while (position < body.instructions.length) {
        final instruction = body.instructions[position];
        type(instruction.resultType);
        if (instruction.resultType == tNever && instruction.value != -1)
          fail('Never operation has a result value');
        if (instruction.value >= 0) {
          define(instruction.value, position);
          if (function.valueTypes[instruction.value] != instruction.resultType)
            fail('result metadata');
        } else if (instruction.value != -1) {
          fail('invalid discarded result');
        }
        position++;
      }
      block++;
    }
  }

  void expectInput(SsaInstruction instruction, int index, int expected) {
    if (inputType(instruction.inputs[index]) != expected) fail('operand type');
  }

  void instruction(SsaInstruction instruction) {
    final SsaInstruction(:op, :target, resultType: result) = instruction;
    var count = 0;
    if (op == opCall || op == opGenericCall) {
      var calleeId = target;
      if (op == opGenericCall) {
        if (target < 0 || target >= genericCalls.length)
          fail('generic call target');
        calleeId = genericCalls[target].function;
      }
      if (calleeId < 0 || calleeId >= functions.length) fail('call target');
      final callee = functions[calleeId];
      count = callee.parameters;
      var expectedResult = callee.result;
      if (op == opGenericCall) {
        var arguments = genericCalls[target].typeArguments;
        if (callee.typeParameters.isEmpty ||
            arguments.length != callee.typeParameters.length)
          fail('generic argument count');
        for (var argument in arguments) type(argument);
        for (var i = 0; i < arguments.length; i++) {
          var bound = substituteType(
            typeParameterInfo(callee.typeParameters[i]).bound,
            callee.typeParameters,
            arguments,
          );
          if (!typeIsSubtype(arguments[i], bound))
            fail('generic argument bound');
        }
        expectedResult = genericBoundaryType(expectedResult);
      } else if (callee.typeParameters.isNotEmpty) {
        fail('generic call requires type arguments');
      }
      if (callee.parameterTypes.length != count || result != expectedResult)
        fail('call metadata');
    } else if (op == opBuiltin) {
      if (!(target >= bPrintString && target <= bLateError ||
          target >= bNativeLoad64 &&
              target <= bNativeResumeContext &&
              target != bNativeMetadataAddress))
        fail('unknown SSA builtin');
      count = instruction.inputs.length;
      if (target >= bNativeLoad64) count = nativeBuiltinArity(target);
      // These normalized representation operations have explicit SSA shapes.
      // General library/primitive signatures remain owned by their producers.
      if (target == bLateError) count = 1;
      if (target >= bBoxDouble && target <= bNumberProperty) {
        count =
            target == bDoubleModulo ||
                target == bDoubleTruncDiv ||
                target == bValueFloatDiv ||
                target == bValueRemainder ||
                target == bValueCompareTo ||
                target == bNumberProperty
            ? 2
            : 1;
      } else if (target >= bBoxInt && target <= bValueBool ||
          target == bFunctionEntry ||
          target == bFunctionType) {
        count = 1;
      } else if (target == bFunctionInvoke && count < 3) {
        fail('invoke operand count');
      } else if (target == bListSublist) {
        count = 4;
      } else if (target == bTypeInstantiate || target == bValueCheck) {
        count = 2;
      } else if (target == bListNewTyped) {
        count = 1;
      } else if (target == bListFilledTyped) {
        count = 4;
      }
    } else if (op == opDoubleNeg ||
        op == opIntToDouble ||
        op == opStoreGlobal ||
        op == opNeg ||
        op == opBitNot ||
        op == opNot ||
        op == opTypeTest ||
        op == opTypeCast) {
      count = 1;
    } else if (op >= opAdd && op <= opGe ||
        op >= opDoubleAdd && op <= opDoubleCompare) {
      count = 2;
    } else if (op != opDouble &&
        op != opInt &&
        op != opString &&
        op != opLoadGlobal &&
        op != opDescriptor &&
        op != opMetadataAddress &&
        op != opConstantData &&
        op != opFunctionReference &&
        op != opClosureDescriptor &&
        op != opCaptureCellDescriptor &&
        op != opLateCellDescriptor &&
        op != opTypeReference &&
        op != opCallShape) {
      fail('unknown SSA operation');
    }
    if (instruction.inputs.length != count) fail('operand count');
    for (var input in instruction.inputs) value(input);
    if (instruction.effects != ssaEffects(op, target))
      fail('operation effects');
    if (op == opStoreGlobal && instruction.value != -1) fail('store result');
    if (op == opCall || op == opGenericCall) {
      var callee = op == opGenericCall ? genericCalls[target].function : target;
      var i = 0;
      while (i < count) {
        var expected = functions[callee].parameterTypes[i];
        if (op == opGenericCall) expected = genericBoundaryType(expected);
        type(expected);
        if (!_compatible(inputType(instruction.inputs[i]), expected))
          fail('call operand type');
        i++;
      }
    } else if (op == opCallShape) {
      if (target < 0 || target >= callShapes.length || result != tInt)
        fail('call shape');
      final shape = callShapes[target];
      if (shape.positional < 0) fail('call positional count');
      for (var i = 0; i < shape.names.length; i++)
        if (shape.names[i] == '' ||
            i > 0 &&
                compareParameterNames(shape.names[i - 1], shape.names[i]) >= 0)
          fail('call name order');
    } else if (op == opTypeReference) {
      type(target);
      if (result != tObject) fail('type reference result');
    } else if (op == opLoadGlobal || op == opStoreGlobal) {
      if (target < 0 || target >= globalTypes.length) fail('global target');
      type(globalTypes[target]);
      if (op == opLoadGlobal && result != globalTypes[target])
        fail('load type');
      if (op == opStoreGlobal &&
          !_compatible(inputType(instruction.inputs[0]), globalTypes[target]))
        fail('store type');
    } else if (op == opInt && result == tDouble) {
      fail('integer constant type');
    } else if (op >= opDouble && op <= opIntToDouble) {
      final expected = op == opDoubleCompare ? tInt : tDouble;
      if (result != expected) fail('double result type');
      for (var i = 0; i < count; i++)
        expectInput(instruction, i, op == opIntToDouble ? tInt : tDouble);
    } else if (op == opString) {
      if (target < 0 || target >= strings.length || result != tString)
        fail('string constant');
    } else if (op == opDescriptor) {
      if (target < 0 || target >= classSizes.length || result != tPointer)
        fail('descriptor constant');
    } else if (op == opConstantData) {
      if (target < 0 || target >= constantData.length || result != tPointer)
        fail('data constant');
    } else if (op == opMetadataAddress) {
      final allowed =
          metadataStrings |
          metadataLists |
          metadataValues |
          metadataRoots |
          metadataFrames |
          metadataHandlers;
      if (target <= 0 || (target & ~allowed) != 0 || result != tInt)
        fail('metadata constant');
    } else if (op == opFunctionReference || op == opClosureDescriptor) {
      if (target < 0 ||
          target >= functions.length ||
          (op == opClosureDescriptor
              ? result != tPointer
              : !typeIsFunction(result)))
        fail('function constant');
      final callee = functions[target];
      if (!callee.callableShape ||
          callee.callableAdapter < 0 ||
          callee.callableAdapter >= functions.length ||
          (op == opFunctionReference && callee.callableType != result))
        fail('callable metadata');
      if (op == opClosureDescriptor) {
        type(callee.callableType);
        if (!typeIsFunction(callee.callableType)) fail('closure signature');
        final closure = callee.closureLayout;
        if (closure == null) fail('closure layout');
        for (final parameter in closure.typeParameters) type(parameter);
        for (final field in closure.fieldTypes) type(field);
        if (closure.boundReceiver &&
            (closure.fieldTypes.length != 1 ||
                callee.parameterTypes.isEmpty ||
                !typeIsClass(closure.fieldTypes[0]) ||
                closure.fieldTypes[0] != callee.parameterTypes[0]))
          fail('bound method receiver');
      }
    } else if (op == opCaptureCellDescriptor || op == opLateCellDescriptor) {
      type(target);
      if (result != tPointer) fail('capture cell descriptor');
    } else if (op == opTypeTest || op == opTypeCast) {
      type(target);
      if (typeContainsParameters(target)) fail('uninstantiated type operation');
      if (!typeIsTagged(inputType(instruction.inputs[0])))
        fail('type operation operand representation');
      if (result != (op == opTypeTest ? tBool : target))
        fail('type operation result');
    } else if (op == opNot) {
      expectInput(instruction, 0, tBool);
      if (result != tBool) fail('boolean result');
    } else if (op >= opEq && op <= opGe) {
      if (result != tBool) fail('comparison result');
      if (op != opEq && op != opNe) {
        expectInput(instruction, 0, tInt);
        expectInput(instruction, 1, tInt);
      }
    } else if (op >= opAdd && op <= opBitNot) {
      var expected = tInt;
      if ((op == opAnd || op == opOr || op == opXor) && result == tBool)
        expected = tBool;
      if (result != expected) fail('arithmetic result');
      var i = 0;
      while (i < count) {
        expectInput(instruction, i, expected);
        i++;
      }
    } else if (op == opBuiltin) {
      if ((target == bValueCast ||
              target == bListNew ||
              target == bListFilled) &&
          typeContainsParameters(result))
        fail('uninstantiated builtin type');
      if (target == bLateError) {
        expectInput(instruction, 0, tInt);
        if (result != tNever) fail('late failure result');
      } else if (target >= bNativeLoad64) {
        for (var input in instruction.inputs) {
          if (inputType(input) != nativeBuiltinInputType(target))
            fail('primitive operand type');
        }
        if (result != nativeBuiltinResultType(target)) fail('primitive result');
      } else if (target == bTypeInstantiate) {
        expectInput(instruction, 0, tObject);
        expectInput(instruction, 1, listType(tObject));
        if (result != tObject) fail('instantiated type reference');
      } else if (target == bValueCheck) {
        if (!typeIsTagged(inputType(instruction.inputs[0])) ||
            !typeIsTagged(result) && !typeIsReference(result))
          fail('generic checked value representation');
        expectInput(instruction, 1, tObject);
      } else if (target == bListNewTyped || target == bListFilledTyped) {
        if (!typeIsList(result)) fail('generic List result');
        if (target == bListNewTyped) {
          expectInput(instruction, 0, tObject);
        } else {
          expectInput(instruction, 0, tInt);
          if (!typeIsTagged(inputType(instruction.inputs[1])))
            fail('generic fill value');
          expectInput(instruction, 2, tBool);
          expectInput(instruction, 3, tObject);
        }
      } else if (target == bListSublist) {
        if (!typeIsList(result) || inputType(instruction.inputs[0]) != result)
          fail('sublist receiver type');
        for (var i = 1; i < 4; i++) expectInput(instruction, i, tInt);
      } else if (target == bBoxInt ||
          target == bBoxDouble ||
          target == bBoxBool) {
        expectInput(
          instruction,
          0,
          target == bBoxInt
              ? tInt
              : target == bBoxDouble
              ? tDouble
              : tBool,
        );
        if (!typeIsTagged(result)) fail('boxed result');
      } else if (target >= bDoubleToString && target <= bNumberProperty) {
        final raw =
            target == bDoubleToString ||
            target == bDoubleModulo ||
            target == bDoubleTruncDiv ||
            target == bDoubleToInt;
        final parsing = target == bDoubleParse || target == bDoubleTryParse;
        for (var i = 0; i < count; i++) {
          if (raw)
            expectInput(instruction, i, tDouble);
          else if (parsing)
            expectInput(instruction, i, tString);
          else if (target == bNumberProperty && i == 1)
            expectInput(instruction, i, tInt);
          else if (!typeIsTagged(inputType(instruction.inputs[i])))
            fail('numeric dispatch operand');
        }
        final expected = target == bDoubleToString
            ? tString
            : target == bDoubleModulo ||
                  target == bDoubleParse ||
                  target == bValueToDouble
            ? tDouble
            : target == bDoubleToInt ||
                  target == bDoubleTruncDiv ||
                  target == bValueToInt ||
                  target == bValueCompareTo
            ? tInt
            : target == bDoubleTryParse
            ? nullableType(tDouble)
            : target == bNumberProperty
            ? tBool
            : -1;
        if (expected >= 0 ? result != expected : !typeIsTagged(result))
          fail('numeric dispatch result');
      } else if (target == bValueBool) {
        if (!typeIsTagged(inputType(instruction.inputs[0])) || result != tBool)
          fail('boolean cast');
      } else if (target == bFunctionEntry ||
          target == bFunctionType ||
          target == bFunctionInvoke) {
        final header = target != bFunctionInvoke;
        final receiver = inputType(instruction.inputs[header ? 0 : 1]);
        if (!typeIsFunction(receiver)) fail('invoke receiver type');
        if (header) {
          if (result != tPointer) fail('entry result');
        } else {
          expectInput(instruction, 0, tPointer);
          expectInput(instruction, 2, tInt);
          final shapeValue = instruction.inputs[2];
          if (positions[shapeValue] < 0) fail('invoke shape is not constant');
          final producer = function
              .blocks[owners[shapeValue]]
              .instructions[positions[shapeValue]];
          if (producer.op != opCallShape) fail('invoke shape producer');
          final shape = callShapes[producer.target];
          final signature = functionSignature(receiver);
          if (count != shape.count + 3 ||
              result != tDynamic ||
              shape.positional < signature.required ||
              shape.positional > signature.positional)
            fail('invoke signature');
          for (final name in shape.names)
            if (signature.namedIndex(name) < 0) fail('invoke named argument');
          for (var i = 0; i < signature.names.length; i++)
            if (signature.requiredNamed[i] &&
                shape.namedIndex(signature.names[i]) < 0)
              fail('invoke required named argument');
          var i = 3;
          while (i < count) {
            if (!typeIsTagged(inputType(instruction.inputs[i])))
              fail('invoke argument representation');
            i++;
          }
        }
      }
      // BoxRef also carries proven flow promotion and unreachable Never values.
      // Other polymorphic builtins retain frontend-owned language type rules.
    }
  }

  void edge(SsaEdge edge) {
    if (edge.target < 0 || edge.target >= function.blocks.length)
      fail('edge target');
    final parameters = function.blocks[edge.target].parameters;
    if (edge.arguments.length != parameters.length) fail('edge arity');
    var i = 0;
    while (i < parameters.length) {
      if (!_compatible(
        inputType(edge.arguments[i]),
        function.valueTypes[parameters[i]],
      ))
        fail('edge operand type');
      i++;
    }
    if (predecessors[edge.target].isEmpty)
      predecessors[edge.target] = <int>[block];
    else
      predecessors[edge.target].add(block);
  }

  void unusedEdge(SsaEdge edge) {
    if (edge.target != -1 || edge.arguments.isNotEmpty) fail('unused edge');
  }

  void structure() {
    block = 0;
    while (block < function.blocks.length) {
      final body = function.blocks[block];
      position = 0;
      while (position < body.instructions.length) {
        final operation = body.instructions[position];
        instruction(operation);
        if (operation.resultType == tNever &&
            (position + 1 != body.instructions.length ||
                body.end.kind != 4 && body.end.kind != 6))
          fail('Never operation has a normal continuation');
        position++;
      }
      final end = body.end;
      if (end.kind == 1) {
        if (end.value != -1) fail('jump value');
        edge(end.first);
        unusedEdge(end.second);
      } else if (end.kind == 2) {
        if (inputType(end.value) != tBool) fail('branch condition type');
        edge(end.first);
        edge(end.second);
      } else if (end.kind == 3) {
        if (function.result == tNever) fail('Never function returns');
        if (!_compatible(inputType(end.value), function.result))
          fail('return type');
        unusedEdge(end.first);
        unusedEdge(end.second);
      } else if (end.kind == 5 || end.kind == 6) {
        if (end.value != -1) fail('invoke value');
        if (body.instructions.isEmpty ||
            (body.instructions.last.effects & ssaThrow) == 0)
          fail('invoke requires a throwing operation');
        final operation = body.instructions.last;
        for (var i = 0; i + 1 < body.instructions.length; i++)
          if ((body.instructions[i].effects & ssaThrow) != 0)
            fail('invoke has an earlier throwing operation');
        if (end.kind == 5) {
          if (operation.resultType == tNever) fail('Never invoke normal edge');
          edge(end.first);
        } else {
          if (operation.resultType != tNever) fail('Never invoke result');
          unusedEdge(end.first);
        }
        edge(end.second);
        for (final argument in end.second.arguments)
          if (argument == operation.value)
            fail('invoke result on exception edge');
      } else if (end.kind == 4) {
        if (end.value != -1) fail('unreachable value');
        unusedEdge(end.first);
        unusedEdge(end.second);
      } else {
        fail('block terminator');
      }
      block++;
    }
  }

  void dominance() {
    final count = function.blocks.length;
    rank = List<int>.filled(count, -1);
    var work = <int>[1];
    var postorder = <int>[];
    while (work.isNotEmpty) {
      final item = work.removeLast();
      if (item < 0) {
        postorder.add(-item - 1);
        continue;
      }
      final current = item - 1;
      if (rank[current] != -1) continue;
      rank[current] = -2;
      work.add(-item);
      final end = function.blocks[current].end;
      for (final next in <int>[
        if (end.hasFirst) end.first.target,
        if (end.hasSecond) end.second.target,
      ]) {
        if (rank[next] == -1) {
          work.add(next + 1);
        }
      }
    }
    final order = <int>[];
    var i = postorder.length;
    while (i > 0) {
      i--;
      rank[postorder[i]] = order.length;
      order.add(postorder[i]);
    }
    final idom = List<int>.filled(count, -1);
    idom[0] = 0;
    var changed = true;
    while (changed) {
      changed = false;
      i = 1;
      while (i < order.length) {
        final current = order[i];
        var parent = -1;
        for (var predecessor in predecessors[current]) {
          if (idom[predecessor] >= 0) {
            if (parent < 0)
              parent = predecessor;
            else {
              var finger = predecessor;
              while (parent != finger) {
                while (rank[parent] > rank[finger]) parent = idom[parent];
                while (rank[finger] > rank[parent]) finger = idom[finger];
              }
            }
          }
        }
        if (idom[current] != parent) {
          idom[current] = parent;
          changed = true;
        }
        i++;
      }
    }
    var children = <List<int>>[];
    i = 0;
    while (i < count) {
      children.add(const <int>[]);
      i++;
    }
    i = 1;
    while (i < order.length) {
      final current = order[i];
      final parent = idom[current];
      if (children[parent].isEmpty)
        children[parent] = <int>[current];
      else
        children[parent].add(current);
      i++;
    }
    entered = List<int>.filled(count, -1);
    exited = List<int>.filled(count, -1);
    work = <int>[1];
    var clock = 0;
    while (work.isNotEmpty) {
      final item = work.removeLast();
      if (item < 0) {
        exited[-item - 1] = clock;
        clock++;
        continue;
      }
      final current = item - 1;
      entered[current] = clock;
      clock++;
      work.add(-item);
      for (var child in children[current]) work.add(child + 1);
    }
  }

  bool reachesWithoutNormal(int owner) {
    while (withoutNormal.length < function.blocks.length)
      withoutNormal.add(null);
    var reached = withoutNormal[owner];
    if (reached == null) {
      reached = List<bool>.filled(function.blocks.length, false);
      final work = <int>[0];
      while (work.isNotEmpty) {
        final current = work.removeLast();
        if (reached[current]) continue;
        reached[current] = true;
        final end = function.blocks[current].end;
        if (end.hasFirst && current != owner) work.add(end.first.target);
        if (end.hasSecond) work.add(end.second.target);
      }
      withoutNormal[owner] = reached;
    }
    return reached[block];
  }

  void use(int id, [bool normalEdge = false]) {
    value(id);
    final owner = owners[id];
    if (owner < 0) fail('undefined value');
    if (owner == block && positions[id] >= position)
      fail('use before definition');
    if (rank[block] >= 0 &&
        (rank[owner] < 0 ||
            entered[owner] > entered[block] ||
            exited[owner] < exited[block]))
      fail('definition does not dominate use');
    final body = function.blocks[owner];
    if (body.end.kind == 5 &&
        body.instructions.last.value == id &&
        !(block == owner && normalEdge) &&
        rank[block] >= 0 &&
        reachesWithoutNormal(owner))
      fail('invoke result is unavailable on this path');
  }

  void uses() {
    block = 0;
    while (block < function.blocks.length) {
      final body = function.blocks[block];
      position = 0;
      while (position < body.instructions.length) {
        for (var input in body.instructions[position].inputs) use(input);
        position++;
      }
      final end = body.end;
      if (end.kind == 2 || end.kind == 3) use(end.value);
      if (end.hasFirst) {
        for (var input in end.first.arguments) use(input, end.kind == 5);
      }
      if (end.hasSecond) {
        for (var input in end.second.arguments) use(input);
      }
      block++;
    }
  }
}

void verifySsa(List<SsaFunction> program) {
  if (program.length != functions.length) ssaError('verify function count');
  var f = 0;
  while (f < program.length) {
    final function = program[f];
    final predecessors = <List<int>>[];
    var b = 0;
    while (b < function.blocks.length) {
      predecessors.add(const <int>[]);
      b++;
    }
    final verifier = _SsaVerifier(
      function,
      f,
      List<int>.filled(function.valueTypes.length, -1),
      List<int>.filled(function.valueTypes.length, -1),
      predecessors,
    );
    verifier.definitions();
    verifier.structure();
    verifier.dominance();
    verifier.uses();
    f++;
  }
}
