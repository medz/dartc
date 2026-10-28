import 'dart:convert';
import 'dart:io';

import '../tool/src/process.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void completed(ProcessOutcome result) {
  check(
    result.exitCode == 0 &&
        !result.timedOut &&
        !result.outputLimited &&
        result.startError == null &&
        result.captureError == null,
    jsonEncode(result.toJson()),
  );
}

String driverSource(Uri library) =>
    '''
import '${library.resolve('frontend.dart')}' as frontend;
import '${library.resolve('host.dart')}' as host;
import '${library.resolve('ir.dart')}';
import '${library.resolve('source.dart')}';
import '${library.resolve('ssa.dart')}';
import '${library.resolve('optimize.dart')}';
import '${library.resolve('types.dart')}';
import '${library.resolve('verify_ssa.dart')}';
import '${library.resolve('machine.dart')}';
import '${library.resolve('allocate.dart')}';
import '${library.resolve('emit.dart')}';
import '${library.resolve('reach.dart')}';
import '${library.resolve('format.dart')}';

SsaFunction named(List<SsaFunction> program, String name) {
  var i = 0;
  while (i < functions.length) {
    if (functions[i].name == name) return program[i];
    i++;
  }
  ssaError('test function missing: ' + name);
}

SsaInstruction operation(SsaFunction function, int op) {
  for (var block in function.blocks) {
    for (var instruction in block.instructions) {
      if (instruction.op == op) return instruction;
    }
  }
  ssaError('test operation missing');
}

int templateParameter() {
  var i = 0;
  while (i < dartTypes.length) {
    if (dartTypes[i].kind == kTypeParameter) return i;
    i++;
  }
  ssaError('test type parameter missing');
}

void corrupt(List<SsaFunction> program, String mode) {
  final order = named(program, 'order');
  final diamond = named(program, 'diamond');
  final add = operation(order, opAdd);
  final call = operation(diamond, opCall);
  if (mode == 'invoke-edge-result' || mode == 'invoke-handler-result' ||
      mode == 'invoke-earlier' || mode == 'invoke-nonthrow') {
    final function = named(program, 'caught');
    for (var block in function.blocks) {
      if (block.end.kind != 5) continue;
      final invoke = block.instructions.last;
      if (invoke.op != opCall || functions[invoke.target].name != 'callee') continue;
      if (mode == 'invoke-edge-result') {
        final id = function.valueTypes.length;
        function.valueTypes.add(tInt);
        function.blocks[block.end.second.target].parameters.add(id);
        block.end.second.arguments.add(invoke.value);
      } else if (mode == 'invoke-handler-result') {
        final id = function.valueTypes.length;
        function.valueTypes.add(tInt);
        function.blocks[block.end.second.target].instructions.insert(0,
          SsaInstruction(opAdd, id, 0, <int>[invoke.value, invoke.value], 0, tInt));
      } else if (mode == 'invoke-earlier') {
        final id = function.valueTypes.length;
        function.valueTypes.add(tInt);
        block.instructions.insert(0, SsaInstruction(opCall, id, invoke.target,
            function.arguments.sublist(0), invoke.effects, tInt));
      } else {
        invoke.op = opInt;
        invoke.target = 0;
        invoke.inputs.clear();
        invoke.effects = 0;
      }
      return;
    }
    ssaError('test invoke missing');
  } else if (mode == 'exit-result' || mode == 'exit-arity' || mode == 'exit-effects') {
    final function = named(program, 'rtHostExit');
    final instruction = operation(function, opBuiltin);
    if (mode == 'exit-result') {
      instruction.resultType = tInt;
    } else if (mode == 'exit-arity') instruction.inputs.clear();
    else instruction.effects = 0;
  } else if (mode == 'never-value' || mode == 'never-continuation' ||
      mode == 'never-after' || mode == 'unreachable-value' ||
      mode == 'unreachable-edge') {
    final function = named(program, 'terminal');
    for (var block in function.blocks) {
      if (block.end.kind != 4 || block.instructions.isEmpty) continue;
      final operation = block.instructions.last;
      if (operation.resultType != tNever) continue;
      if (mode == 'never-value') {
        operation.value = function.valueTypes.length;
        function.valueTypes.add(tNever);
      } else if (mode == 'never-continuation') {
        block.end = SsaTerminator(1, -1, SsaEdge(0, <int>[]), SsaEdge(-1, <int>[]));
      } else if (mode == 'never-after') {
        block.instructions.add(SsaInstruction(opInt, -1, 0, <int>[], 0, tInt));
      } else if (mode == 'unreachable-value') {
        block.end.value = function.arguments[0];
      } else {
        block.end.first = SsaEdge(0, <int>[]);
      }
      return;
    }
    ssaError('test terminal operation missing');
  } else if (mode == 'late-cell-type') {
    operation(named(program, 'delayed'), opLateCellDescriptor).target = -1;
  } else if (mode == 'late-error-arity') {
    for (var function in program) {
      for (var block in function.blocks) {
        for (var instruction in block.instructions) {
          if (instruction.op == opBuiltin && instruction.target == bLateError) {
            instruction.inputs.clear();
            return;
          }
        }
      }
    }
    ssaError('late failure missing');
  } else if (mode == 'double-literal') {
    operation(named(program, 'floating'), opDouble).op = opInt;
  } else if (mode == 'double-arity' || mode == 'double-operand' || mode == 'double-result') {
    final function = named(program, 'floating');
    final floatingAdd = operation(function, opDoubleAdd);
    if (mode == 'double-arity') floatingAdd.inputs.removeLast();
    else if (mode == 'double-result') {
      floatingAdd.resultType = tInt;
      function.valueTypes[floatingAdd.value] = tInt;
    } else {
      final literal = operation(function, opDouble);
      literal.op = opInt;
      literal.resultType = tInt;
      function.valueTypes[literal.value] = tInt;
    }
  } else if (mode == 'generic-count' || mode == 'generic-bound' || mode == 'generic-environment') {
    final invoke = operation(named(program, 'main'), opGenericCall);
    final arguments = genericCalls[invoke.target].typeArguments;
    if (mode == 'generic-count')
      arguments.removeLast();
    else if (mode == 'generic-bound')
      arguments[0] = tString;
    else
      invoke.inputs[0] = invoke.inputs[1];
  } else if (mode == 'type-reference-scope') {
    operation(named(program, 'genericList'), opTypeReference).target = templateParameter();
  } else if (mode == 'closure-environment' || mode == 'closure-scope') {
    final reference = operation(named(program, 'genericClosure'), opClosureDescriptor);
    final info = functions[reference.target];
    if (mode == 'closure-environment') {
      info.closureLayout!.fieldTypes[0] = tInt;
    } else {
      functions[info.callableAdapter].closureLayout = ClosureLayout(
        info.closureLayout!.fieldTypes,
        false,
        <int>[templateParameter()],
      );
    }
  } else if (mode == 'duplicate') {
    operation(order, opMul).value = add.value;
  } else if (mode == 'undefined') {
    add.inputs[0] = order.valueTypes.length;
    order.valueTypes.add(tInt);
  } else if (mode == 'invalid-value') {
    add.inputs[0] = order.valueTypes.length;
  } else if (mode == 'metadata') {
    order.valueTypes[add.value] = tBool;
  } else if (mode == 'type-parameter' || mode == 'nested-type-parameter') {
    var type = templateParameter();
    if (mode == 'nested-type-parameter')
      type = functionType(nullableType(type), <int>[listType(type)]);
    order.valueTypes[add.value] = type;
    add.resultType = type;
  } else if (mode == 'schema-hole' || mode == 'nested-schema-hole') {
    var type = typeSchemaHole();
    if (mode == 'nested-schema-hole')
      type = functionType(nullableType(type), <int>[listType(type)]);
    order.valueTypes[add.value] = type;
    add.resultType = type;
  } else if (mode == 'format-schema-hole') {
    operation(named(program, 'tested'), opTypeTest).target = listType(typeSchemaHole());
  } else if (mode == 'format-type-parameter') {
    operation(named(program, 'tested'), opTypeTest).target = templateParameter();
  } else if (mode == 'order') {
    add.inputs[0] = operation(order, opMul).value;
  } else if (mode == 'dominance') {
    operation(diamond, opAdd).inputs[0] = call.value;
  } else if (mode == 'edge-target') {
    order.blocks[0].end.first.target = order.blocks.length;
  } else if (mode == 'edge-arity' || mode == 'edge-type') {
    for (var block in diamond.blocks) {
      final edge = block.end.first;
      if (edge.arguments.isNotEmpty) {
        if (mode == 'edge-arity') {
          edge.arguments.removeLast();
        } else {
          edge.arguments[0] = diamond.arguments[0];
        }
        return;
      }
    }
    ssaError('test edge missing');
  } else if (mode == 'branch-type') {
    for (var block in diamond.blocks) {
      if (block.end.kind == 2) {
        block.end.value = diamond.arguments[1];
        return;
      }
    }
    ssaError('test branch missing');
  } else if (mode == 'call-target') {
    call.target = functions.length;
  } else if (mode == 'call-arity') {
    call.inputs.add(call.inputs[0]);
  } else if (mode == 'call-type') {
    call.inputs[0] = diamond.arguments[0];
  } else if (mode == 'effects') {
    operation(named(program, 'dropped'), opTypeCast).effects = 0;
  } else if (mode == 'cast-representation') {
    final checked = named(program, 'checked');
    final value = checked.valueTypes.length;
    checked.valueTypes.add(tInt);
    for (var block in checked.blocks) {
      final instructions = <SsaInstruction>[];
      for (var instruction in block.instructions) {
        if (instruction.op == opTypeCast) {
          instructions.add(SsaInstruction(opInt, value, 1, <int>[], 0, tInt));
          instruction.inputs[0] = value;
        }
        instructions.add(instruction);
      }
      block.instructions = instructions;
    }
  } else if (mode == 'callable') {
    final reference = operation(named(program, 'main'), opFunctionReference);
    functions[reference.target].callableAdapter = -1;
  } else if (mode == 'callable-type') {
    final reference = operation(named(program, 'main'), opFunctionReference);
    functions[reference.target].callableType = tFunction;
  } else if (mode == 'bound-receiver-type') {
    final descriptor = operation(named(program, 'main'), opClosureDescriptor);
    functions[descriptor.target].closureLayout!.fieldTypes[0] = tInt;
  } else if (mode == 'unknown-builtin') {
    final invoke = operation(named(program, 'apply'), opBuiltin);
    invoke.target = -1;
  } else if (mode == 'sublist-arity' || mode == 'sublist-index') {
    final slice = operation(named(program, 'slice'), opBuiltin);
    if (mode == 'sublist-arity') slice.inputs.removeLast();
    else slice.inputs[1] = slice.inputs[0];
  } else if (mode == 'valid') {
    // Unused metadata IDs and well-formed unreachable blocks are permitted.
    order.valueTypes.add(tString);
    final value = order.valueTypes.length;
    order.valueTypes.add(tInt);
    order.blocks.add(SsaBlock(
      <int>[],
      <int>[],
      <SsaInstruction>[SsaInstruction(opInt, value, 7, <int>[], 0, tInt)],
      SsaTerminator(3, value, SsaEdge(-1, <int>[]), SsaEdge(-1, <int>[])),
    ));
  } else {
    ssaError('unknown test case');
  }
}

void main(List<String> args) {
  targetOS = host.hostTarget();
  frontend.parseSource(collectSources(args[0], args[1], null, targetOS));
  final program = buildSsa();
  verifySsa(program);
  optimizeSsa(program);
  verifySsa(program);
  corrupt(program, args[2]);
  final format = args[2] == 'format-type-parameter' || args[2] == 'format-schema-hole';
  if (!format) verifySsa(program);
  if (args[2] == 'valid' || format) {
    final selected = selectMachine(program, reachableFunctions(program));
    allocateRegisters(selected);
    generateCode(selected);
    createExecutable();
  }
  print('SSA verified');
}
''';

const taskSource = '''
typedef UnusedTemplate<T> = List<T>;
class Counter { int add(int value) => value + 1; }
T generic<T extends num>(T value) => value;
List<T> genericList<T>(T value) => [value];
T Function(T) genericClosure<T>() => (T value) => value;
double floating(double value) => value + 0.25;
int Function() delayed(int value) {
  late final int result = value + 1;
  return () => result;
}
int callee(int value) => value + 1;
int caught(int value) {
  var result = value;
  try { result = callee(value); } catch (_) { result += 2; }
  return result;
}
Never terminal(dynamic value) => value as Never;
int order(int value) {
  final next = value + 1;
  return next * 2;
}
int diamond(bool choice, int value) {
  var result = 0;
  if (choice) {
    result = callee(value);
  } else {
    result = value + 2;
  }
  return result;
}
int loop(int count) {
  var result = 0;
  while (count > 0) {
    result = result + count;
    count = count - 1;
  }
  return result;
}
int checked(dynamic value) => value as int;
bool tested(dynamic value) => value is int;
void dropped(dynamic value) { value as int; }
int apply(int Function(int) function, int value) => function(value);
List<int> slice(List<int> value) => value.sublist(1);
void main() {
  print(caught(9));
  print(delayed(1)());
  print(generic<int>(1));
  print(genericList<int>(2));
  print(genericClosure<int>()(3));
  print(floating(1.5));
  print(order(3));
  print(diamond(true, 4));
  print(loop(3));
  print(checked(7));
  print(tested(7));
  dropped(1);
  print(apply(callee, 8));
  print(apply(Counter().add, 9));
  print(slice([1, 2]));
}
''';

Future<void> main(List<String> args) async {
  if (args.length != 4 || args[0] != '--compiler' || args[2] != '--std') {
    stderr.writeln(
      'Usage: dart test/ssa_test.dart --compiler <native compiler> --std <runtime.dart>',
    );
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final compiler = File(args[1]).absolute.path;
  final standard = File(args[3]).absolute.path;
  final work = Directory.systemTemp.createTempSync('dartc-ssa-test-');
  var passed = false;
  try {
    final driver = File('${work.path}/driver.dart');
    driver.writeAsStringSync(driverSource(root.uri.resolve('lib/src/')));
    final source = File('${work.path}/task.dart');
    source.writeAsStringSync(taskSource);
    final executable = '${work.path}/driver';
    completed(
      await captureProcess(
        compiler,
        [driver.path, '--std', standard, '-o', executable],
        workingDirectory: work.path,
        environment: const {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'},
        includeParentEnvironment: false,
      ),
    );
    const cases = {
      'valid': '',
      'invoke-edge-result': 'invoke result on exception edge',
      'invoke-handler-result': 'invoke result is unavailable on this path',
      'invoke-earlier': 'invoke has an earlier throwing operation',
      'invoke-nonthrow': 'invoke requires a throwing operation',
      'exit-result': 'primitive result',
      'exit-arity': 'operand count',
      'exit-effects': 'operation effects',
      'never-value': 'Never operation has a result value',
      'never-continuation': 'Never operation has a normal continuation',
      'never-after': 'Never operation has a normal continuation',
      'unreachable-value': 'unreachable value',
      'unreachable-edge': 'unused edge',
      'late-cell-type': 'invalid type',
      'late-error-arity': 'operand count',
      'double-literal': 'integer constant type',
      'double-arity': 'operand count',
      'double-operand': 'operand type',
      'double-result': 'double result type',
      'generic-count': 'generic argument count',
      'generic-bound': 'generic argument bound',
      'generic-environment': 'call operand type',
      'closure-environment': 'closure type environment layout',
      'closure-scope': 'closure type environment scope',
      'type-reference-scope': 'uninstantiated executable type',
      'duplicate': 'duplicate definition',
      'undefined': 'undefined value',
      'invalid-value': 'invalid value',
      'metadata': 'result metadata',
      'type-parameter': 'uninstantiated executable type',
      'schema-hole': 'uninstantiated executable type',
      'nested-schema-hole': 'uninstantiated executable type',
      'format-schema-hole': 'uninstantiated runtime type',
      'nested-type-parameter': 'uninstantiated executable type',
      'format-type-parameter': 'uninstantiated runtime type',
      'order': 'use before definition',
      'dominance': 'definition does not dominate use',
      'edge-target': 'edge target',
      'edge-arity': 'edge arity',
      'edge-type': 'edge operand type',
      'branch-type': 'branch condition type',
      'call-target': 'call target',
      'call-arity': 'operand count',
      'call-type': 'call operand type',
      'effects': 'operation effects',
      'cast-representation': 'type operation operand representation',
      'callable': 'callable metadata',
      'callable-type': 'callable metadata',
      'bound-receiver-type': 'bound method receiver',
      'unknown-builtin': 'unknown SSA builtin',
      'sublist-arity': 'operand count',
      'sublist-index': 'operand type',
    };
    for (final entry in cases.entries) {
      final result = await captureProcess(
        executable,
        [source.uri.toString(), File(standard).uri.toString(), entry.key],
        workingDirectory: work.path,
        environment: const {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'},
        includeParentEnvironment: false,
      );
      check(
        !result.timedOut &&
            !result.outputLimited &&
            result.startError == null &&
            result.captureError == null,
        jsonEncode(result.toJson()),
      );
      if (entry.key == 'valid') {
        completed(result);
        check(result.stdout == 'SSA verified\n', result.stdout);
      } else {
        final prefix =
            (entry.key == 'format-type-parameter' ||
                entry.key == 'format-schema-hole')
            ? 'dartc: uninstantiated runtime type'
            : 'dartc SSA: verify ';
        check(
          result.exitCode == 1 &&
              result.stdout.startsWith(prefix) &&
              result.stdout.contains(entry.value),
          '${entry.key}: ${jsonEncode(result.toJson())}',
        );
      }
    }
    passed = true;
    stdout.writeln('Native SSA verification passed.');
  } finally {
    if (passed) {
      work.deleteSync(recursive: true);
    } else {
      stderr.writeln('SSA work retained at: ${work.path}');
    }
  }
}
