import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

import '../../support/runtime.dart';

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

  final initializeState = FunctionTarget(uri, 'initialize_state', .integer, []);
  final stateEntry = Block([])..finish(Return(const Constant.integer(7)));
  final state = GlobalVariable(
    uri,
    'state',
    .integer,
    initializer: initializeState,
  );
  final readState = FunctionTarget(uri, 'heap_read_state', .integer, []);
  final readEntry = Block([]);
  readEntry.finish(Return(readEntry.emit(LoadGlobal(state))));
  final writeState = FunctionTarget(uri, 'heap_write_state', .voidType, [
    .integer,
  ]);
  final writeEntry = Block(writeState.parameterTypes);
  writeEntry.emit(StoreGlobal(state, writeEntry.parameters.single));
  writeEntry.finish(const Return());
  final initializeShared = FunctionTarget(uri, 'initialize_shared', node, []);
  final sharedEntry = Block([]);
  sharedEntry.finish(
    Return(
      sharedEntry.emit(
        Construct(ctor, [
          const Constant.integer(100),
          const Constant.nullValue(),
        ]),
      ),
    ),
  );
  final shared = GlobalVariable(
    uri,
    'shared',
    node,
    initializer: initializeShared,
  );
  final mutateShared = FunctionTarget(uri, 'heap_mutate_shared', .integer, [
    .integer,
  ]);
  final mutateEntry = Block(mutateShared.parameterTypes);
  final sharedObject = mutateEntry.emit(LoadGlobal(shared));
  final updated = mutateEntry.emit(
    IntBinary(
      .add,
      mutateEntry.emit(LoadField(value, sharedObject)),
      mutateEntry.parameters.single,
    ),
  );
  mutateEntry.emit(StoreField(value, sharedObject, updated));
  mutateEntry.finish(Return(updated));
  final globalReenter = FunctionTarget(
    uri,
    'heap_global_reenter',
    .integer,
    reenter.parameterTypes,
  );
  final globalEntry = Block(globalReenter.parameterTypes);
  // Keep an alias in the suspended frame as well as in the global holder.
  final sharedAlias = globalEntry.emit(LoadGlobal(shared));
  final retainedResult = globalEntry.emit(
    DirectCall(reenter, globalEntry.parameters),
  );
  globalEntry.finish(
    Return(
      globalEntry.emit(
        IntBinary(
          .add,
          globalEntry.emit(
            IntBinary(
              .add,
              retainedResult,
              globalEntry.emit(LoadGlobal(state)),
            ),
          ),
          globalEntry.emit(
            IntBinary(
              .add,
              globalEntry.emit(LoadField(value, sharedAlias)),
              globalEntry.emit(
                LoadField(value, globalEntry.emit(LoadGlobal(shared))),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  functions.addAll([
    IrFunction(initializeShared, [sharedEntry]),
    IrFunction(mutateShared, [mutateEntry]),
    IrFunction(initializeState, [stateEntry]),
    IrFunction(readState, [readEntry]),
    IrFunction(writeState, [writeEntry]),
    IrFunction(globalReenter, [globalEntry]),
  ]);

  final pointerType = NativePointerType(NativeScalarType(Void));
  final comparatorType = NativePointerType(
    NativeFunctionType(
      NativeSignature.types(NativeScalarType(Int32), [
        pointerType,
        pointerType,
      ]),
    ),
  );
  final qsortSignature = NativeSignature.types(NativeScalarType(Void), [
    pointerType,
    NativeScalarType(Uint64),
    NativeScalarType(Uint64),
    comparatorType,
  ]);
  final qsort = FunctionTarget(uri, 'qsort', .voidType, [
    FfiTypes.resolve(pointerType),
    ValueType.integer,
    ValueType.integer,
    FfiTypes.resolve(comparatorType),
  ]);
  final importedReenter = FunctionTarget(
    uri,
    'heap_imported_reenter',
    .integer,
    [FfiTypes.resolve(pointerType), FfiTypes.resolve(comparatorType)],
  );
  final importedEntry = Block(importedReenter.parameterTypes);
  final importedLocal = importedEntry.emit(
    Construct(ctor, [const Constant.integer(42), const Constant.nullValue()]),
  );
  final importedAlias = importedEntry.emit(LoadGlobal(shared));
  importedEntry.emit(
    DirectCall(qsort, [
      importedEntry.parameters[0],
      const Constant.integer(2),
      const Constant.integer(8),
      importedEntry.parameters[1],
    ]),
  );
  importedEntry.finish(
    Return(
      importedEntry.emit(
        IntBinary(
          .add,
          importedEntry.emit(LoadField(value, importedLocal)),
          importedEntry.emit(
            IntBinary(
              .add,
              importedEntry.emit(LoadField(value, importedAlias)),
              importedEntry.emit(
                LoadField(value, importedEntry.emit(LoadGlobal(shared))),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  functions.add(IrFunction(importedReenter, [importedEntry]));

  final program = IrProgram(
    [
      IrClass(node, [value, next], constructors: [ctor, nestedCtor]),
    ],
    functions,
    globals: [state, shared],
    externals: [IrExternal(qsort)],
  );
  final CodeGenerator generator = target.architecture == .arm64
      ? Arm64CodeGenerator(target)
      : X64CodeGenerator(target);
  return generator.generate(
    program,
    runtime: heapRuntime,
    definitions: [...functions.map((f) => f.target), qsort],
    imports: {qsort: NativeImport('qsort', qsortSignature)},
    exports: {
      importedReenter: NativeExport(
        importedReenter.name,
        NativeSignature.types(NativeScalarType(Int64), [
          pointerType,
          comparatorType,
        ]),
      ),
      mutateShared: NativeExport(
        mutateShared.name,
        NativeSignature(Int64, [Int64]),
      ),
      readState: NativeExport(readState.name, NativeSignature(Int64, [])),
      writeState: NativeExport(writeState.name, NativeSignature(Void, [Int64])),
      globalReenter: NativeExport(
        globalReenter.name,
        NativeSignature.types(NativeScalarType(Int64), [
          callbackType,
          NativeScalarType(Int64),
        ]),
      ),
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
