import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

ObjectModule managedHeap(Target target) {
  final uri = Uri.parse('memory:managed-heap');
  final node = ClassType(uri, 'Node');
  final value = InstanceField(node, 'value', .integer);
  final next = InstanceField(node, 'next', node.nullable);
  final ctor = FunctionTarget(
    uri,
    'Node',
    .voidType,
    [.integer, node.nullable],
    owner: node,
    kind: .initializer,
  );
  final init = Block(ctor.parameterTypes);
  init.emit(StoreField(value, init.parameters[0], init.parameters[1]));
  init.emit(StoreField(next, init.parameters[0], init.parameters[2]));
  init.finish(const Return());
  final functions = <IrFunction>[
    IrFunction(ctor, [init]),
  ];
  final chain = FunctionTarget(uri, 'heap_chain', .integer, [.integer]);
  final entry = Block(chain.parameterTypes),
      loop = Block([.integer, node.nullable]);
  final append = Block(),
      read = Block([node.nullable, .integer]),
      item = Block([node, .integer]),
      done = Block();
  entry.finish(
    Jump(loop, [const Constant.integer(0), const Constant.nullValue()]),
  );
  final [index, head] = loop.parameters;
  loop.finish(
    Branch(
      loop.emit(IntBinary(.lessThan, index, entry.parameters.single)),
      Jump(append),
      Jump(read, [head, const Constant.integer(0)]),
    ),
  );
  final object = append.emit(Construct(ctor, [index, head]));
  append.finish(
    Jump(loop, [
      append.emit(IntBinary(.add, index, const Constant.integer(1))),
      object,
    ]),
  );
  final [current, sum] = read.parameters;
  final present = read.emit(TypeTest(current, node));
  read.finish(
    Branch(present, Jump(item, [present.refinement(true)!, sum]), Jump(done)),
  );
  final total = item.emit(
    IntBinary(
      .add,
      item.parameters[1],
      item.emit(LoadField(value, item.parameters[0])),
    ),
  );
  item.finish(
    Jump(read, [item.emit(LoadField(next, item.parameters[0])), total]),
  );
  done.finish(Return(sum));
  functions.add(IrFunction(chain, [entry, loop, append, read, item, done]));

  final cycles = FunctionTarget(uri, 'heap_cycles', .integer, [.integer]);
  final begin = Block(cycles.parameterTypes),
      repeat = Block([.integer]),
      garbage = Block();
  final check = Block(), alias = Block([node]), invalid = Block();
  final live = begin.emit(
    Construct(ctor, [const Constant.integer(-1), const Constant.nullValue()]),
  );
  begin.emit(StoreField(next, live, live));
  begin.finish(Jump(repeat, [const Constant.integer(0)]));
  final iteration = repeat.parameters.single;
  repeat.finish(
    Branch(
      repeat.emit(IntBinary(.lessThan, iteration, begin.parameters.single)),
      Jump(garbage),
      Jump(check),
    ),
  );
  final dead = garbage.emit(
    Construct(ctor, [iteration, const Constant.nullValue()]),
  );
  garbage.emit(StoreField(next, dead, dead));
  garbage.emit(StoreField(value, live, iteration));
  garbage.finish(
    Jump(repeat, [
      garbage.emit(IntBinary(.add, iteration, const Constant.integer(1))),
    ]),
  );
  final reference = check.emit(LoadField(next, live));
  final isNode = check.emit(TypeTest(reference, node));
  check.finish(
    Branch(isNode, Jump(alias, [isNode.refinement(true)!]), Jump(invalid)),
  );
  alias.emit(StoreField(value, live, const Constant.integer(123)));
  alias.finish(Return(alias.emit(LoadField(value, alias.parameters.single))));
  invalid.finish(Return(const Constant.integer(-1)));
  functions.add(
    IrFunction(cycles, [begin, repeat, garbage, check, alias, invalid]),
  );

  final nestedCtor = FunctionTarget(
    uri,
    'Node.nested',
    .voidType,
    [...List.filled(10, node), ValueType.integer],
    owner: node,
    kind: .initializer,
  );
  final nestedBody = Block(nestedCtor.parameterTypes);
  Value nestedSum = nestedBody.emit(
    DirectCall(chain, [nestedBody.parameters.last]),
  );
  for (final argument in nestedBody.parameters.skip(1).take(10)) {
    nestedSum = nestedBody.emit(
      IntBinary(.add, nestedSum, nestedBody.emit(LoadField(value, argument))),
    );
  }
  nestedBody.emit(StoreField(value, nestedBody.parameters.first, nestedSum));
  nestedBody.emit(
    StoreField(next, nestedBody.parameters.first, nestedBody.parameters[10]),
  );
  nestedBody.finish(const Return());
  functions.add(IrFunction(nestedCtor, [nestedBody]));

  final nested = FunctionTarget(
    uri,
    'heap_nested',
    .integer,
    List.filled(10, .integer),
  );
  final nestedEntry = Block(nested.parameterTypes);
  final arguments = [
    for (var i = 0; i < 10; i++)
      nestedEntry.emit(
        Construct(ctor, [Constant.integer(i), const Constant.nullValue()]),
      ),
  ];
  final result = nestedEntry.emit(
    Construct(nestedCtor, [...arguments, nestedEntry.parameters.last]),
  );
  Value nestedResult = nestedEntry.emit(LoadField(value, result));
  for (final parameter in nestedEntry.parameters.take(9)) {
    nestedResult = nestedEntry.emit(IntBinary(.add, nestedResult, parameter));
  }
  nestedEntry.finish(Return(nestedResult));
  functions.add(IrFunction(nested, [nestedEntry]));

  final callbackType = NativePointerType(
    NativeFunctionType(NativeSignature(Void, [Int64])),
  );
  final reenter = FunctionTarget(uri, 'heap_reenter', .integer, [
    FfiTypes.resolve(callbackType),
    ValueType.integer,
  ]);
  final reentry = Block(reenter.parameterTypes);
  final retained = reentry.emit(
    Construct(ctor, [const Constant.integer(42), const Constant.nullValue()]),
  );
  reentry.emit(NativeCall(reentry.parameters[0], [reentry.parameters[1]]));
  reentry.emit(DirectCall(chain, [reentry.parameters[1]]));
  reentry.finish(Return(reentry.emit(LoadField(value, retained))));
  functions.add(IrFunction(reenter, [reentry]));

  final program = IrProgram([
    IrClass(node, [value, next], constructors: [ctor, nestedCtor]),
  ], functions);
  final CodeGenerator generator = target.architecture == .arm64
      ? Arm64CodeGenerator(target)
      : X64CodeGenerator(target);
  return generator.generate(
    program,
    definitions: functions.map((f) => f.target),
    exports: {
      for (final function in [chain, cycles])
        function: NativeExport(function.name, NativeSignature(Int64, [Int64])),
      nested: NativeExport(
        nested.name,
        NativeSignature(Int64, [...List.filled(9, Int8), Int64]),
      ),
      reenter: NativeExport(
        reenter.name,
        NativeSignature.types(NativeScalarType(Int64), [
          callbackType,
          NativeScalarType(Int64),
        ]),
      ),
    },
  );
}
