import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

import '../../support/runtime.dart';

ObjectModule weakHeap(Target target) {
  final uri = Uri.parse('memory:weak-heap');
  final node = ClassType(uri, 'Node');
  final next = InstanceField(node, 'next', node.nullable);
  final constructor = FunctionTarget(
    uri,
    'new',
    .voidType,
    [node.nullable],
    owner: node,
    kind: .initializer,
  );
  final init = Block(constructor.parameterTypes);
  init.emit(StoreField(next, init.parameters[0], init.parameters[1]));
  init.finish(const Return());
  final functions = <IrFunction>[
    IrFunction(constructor, [init]),
  ];
  final classes = <IrClass>[
    IrClass(node, [next], constructors: [constructor]),
  ];
  final exports = <FunctionTarget, NativeExport>{};
  final churn = FunctionTarget(uri, 'churn', .voidType, [.integer]);
  final start = Block(churn.parameterTypes),
      loop = Block([.integer]),
      append = Block(),
      done = Block();
  start.finish(Jump(loop, [const Constant.integer(0)]));
  loop.finish(
    Branch(
      loop.emit(
        IntBinary(.lessThan, loop.parameters.single, start.parameters.single),
      ),
      Jump(append),
      Jump(done),
    ),
  );
  append.emit(Construct(constructor, [const Constant.nullValue()]));
  append.finish(
    Jump(loop, [
      append.emit(
        IntBinary(.add, loop.parameters.single, const Constant.integer(1)),
      ),
    ]),
  );
  done.finish(const Return());
  functions.add(IrFunction(churn, [start, loop, append, done]));

  for (final conditional in [false, true]) {
    final box = ClassType(uri, conditional ? 'Conditional' : 'Weak');
    final key = InstanceField(box, 'key', node.nullable),
        value = InstanceField(box, 'value', node.nullable);
    final ctor = FunctionTarget(
      uri,
      'new',
      .voidType,
      [node, node],
      owner: box,
      kind: .initializer,
    );
    final initialize = Block(ctor.parameterTypes);
    initialize.emit(
      StoreField(key, initialize.parameters[0], initialize.parameters[1]),
    );
    initialize.emit(
      StoreField(value, initialize.parameters[0], initialize.parameters[2]),
    );
    initialize.finish(const Return());
    functions.add(IrFunction(ctor, [initialize]));
    classes.add(
      IrClass(
        box,
        [key, value],
        constructors: [ctor],
        weakFields: conditional ? [] : [key, value],
        ephemerons: conditional ? {key: value} : {},
      ),
    );
    final create = FunctionTarget(uri, 'create${box.name}', box, []);
    final make = Block();
    final a = make.emit(Construct(constructor, [const Constant.nullValue()]));
    final b = make.emit(Construct(constructor, [a]));
    make.finish(Return(make.emit(Construct(ctor, [a, b]))));
    functions.add(IrFunction(create, [make]));

    final test = FunctionTarget(
      uri,
      conditional ? 'ephemeron' : 'weak',
      .integer,
      [.integer, .integer],
    );
    final entry = Block(test.parameterTypes),
        retain = Block(),
        discard = Block(),
        collect = Block([node.nullable]);
    final object = entry.emit(DirectCall(create, []));
    entry.finish(
      Branch(
        entry.emit(Equals(entry.parameters.first, const Constant.integer(1))),
        Jump(retain),
        Jump(discard),
      ),
    );
    retain.finish(Jump(collect, [retain.emit(LoadField(key, object))]));
    discard.finish(Jump(collect, [const Constant.nullValue()]));
    collect.emit(DirectCall(churn, [entry.parameters.last]));
    final observedKey = collect.emit(LoadField(key, object)),
        observedValue = collect.emit(LoadField(value, object));
    final keyMatches = collect.emit(
      Identical(observedKey, collect.parameters.single),
    );
    final inspect = Block(),
        fail = Block()..finish(const Return(Constant.integer(0)));
    collect.finish(Branch(keyMatches, Jump(inspect), Jump(fail)));
    final shouldSurvive = conditional
        ? inspect.emit(
            Equals(entry.parameters.first, const Constant.integer(1)),
          )
        : const Constant.boolean(false);
    final hasValue = inspect.emit(
      TypeTest(observedValue, .nullType, negated: true),
    );
    final pass = Block()..finish(const Return(Constant.integer(1)));
    inspect.finish(
      Branch(
        inspect.emit(Equals(hasValue, shouldSurvive)),
        Jump(pass),
        Jump(fail),
      ),
    );
    functions.add(
      IrFunction(test, [entry, retain, discard, collect, inspect, pass, fail]),
    );
    exports[test] = NativeExport(
      test.name,
      NativeSignature(Int8, [Int8, Int64]),
    );
  }
  final program = IrProgram(classes, functions);
  final CodeGenerator generator = target.architecture == .arm64
      ? Arm64CodeGenerator(target)
      : X64CodeGenerator(target);
  return generator.generate(
    program,
    definitions: reachableDefinitions(program, exports.keys),
    exports: exports,
    runtime: heapRuntime,
  );
}
