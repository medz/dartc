import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

import '../../support/runtime.dart';

ObjectModule exceptions(Target target) {
  final uri = Uri.parse('memory:exceptions');
  final node = ClassType(uri, 'Payload');
  final error = ClassType(uri, 'Failure', superclass: ValueType.error);
  final classes = <IrClass>[IrClass(ValueType.error, [])];
  final bodies = <IrFunction>[];
  final constructors = <ClassType, FunctionTarget>{};
  final fields = <ClassType, InstanceField>{};
  for (final type in [node, error]) {
    final field = fields[type] = InstanceField(type, 'value', .integer);
    final ctor = constructors[type] = FunctionTarget(
      uri,
      type.name,
      .voidType,
      [.integer],
      owner: type,
      kind: .initializer,
    );
    final init = Block(ctor.parameterTypes);
    init.emit(StoreField(field, init.parameters.first, init.parameters.last));
    init.finish(const Return());
    classes.add(IrClass(type, [field], constructors: [ctor]));
    bodies.add(IrFunction(ctor, [init]));
  }

  final churn = FunctionTarget(uri, 'churn', .voidType, [.integer]);
  final start = Block(churn.parameterTypes), loop = Block([.integer]);
  final allocate = Block(), done = Block();
  start.finish(Jump(loop, [const Constant.integer(0)]));
  final i = loop.parameters.single;
  loop.finish(
    Branch(
      loop.emit(IntBinary(.lessThan, i, start.parameters.single)),
      Jump(allocate),
      Jump(done),
    ),
  );
  allocate.emit(Construct(constructors[node]!, [i]));
  allocate.finish(
    Jump(loop, [allocate.emit(IntBinary(.add, i, const Constant.integer(1)))]),
  );
  done.finish(const Return());
  bodies.add(IrFunction(churn, [start, loop, allocate, done]));

  final thrower = FunctionTarget(uri, 'thrower', .never, [.object]);
  final thrown = Block(thrower.parameterTypes);
  thrown.finish(Throw(thrown.parameters.single));
  bodies.add(IrFunction(thrower, [thrown]));
  final relay = FunctionTarget(uri, 'relay', .voidType, [.object]);
  final forwarded = Block(relay.parameterTypes);
  forwarded.finish(
    Unreachable(forwarded.emit(DirectCall(thrower, forwarded.parameters))),
  );
  bodies.add(IrFunction(relay, [forwarded]));

  final capture = FunctionTarget(uri, 'captureAndRethrow', .voidType, [
    .object,
    .integer,
    .integer,
    .integer,
  ]);
  final fresh = FunctionTarget(
    uri,
    'throwAgain',
    .voidType,
    capture.parameterTypes,
  );
  final probeType = FfiTypes.resolve(
    NativePointerType(NativeFunctionType(NativeSignature(Int64, [Int64]))),
  );
  void probe(Block block, Value address, Value callback) {
    block.emit(
      NativeCall(block.emit(PointerFromAddress(address, probeType)), [
        callback,
      ]),
    );
  }

  for (final (function, callee, preserveTrace) in [
    (capture, relay, true),
    (fresh, capture, false),
  ]) {
    final entry = Block(function.parameterTypes), normal = Block();
    final handler = Block([.object, .stackTrace]);
    final again = preserveTrace ? null : Block([.object]);
    final [payload, count, address, callback] = entry.parameters;
    final operation = DirectCall(
      callee,
      preserveTrace ? [payload] : entry.parameters,
    );
    entry.finish(
      Invoke(
        operation,
        onReturn: Jump(normal),
        onThrow: Jump(handler, [UnwindValue.exception, UnwindValue.stackTrace]),
      ),
    );
    normal.finish(const Return());
    probe(handler, address, callback);
    if (preserveTrace) handler.emit(DirectCall(churn, [count]));
    handler.finish(
      Throw(
        handler.parameters.first,
        stackTrace: handler.parameters.last,
        onThrow: again == null ? null : Jump(again, [UnwindValue.exception]),
      ),
    );
    if (again != null) again.finish(Throw(again.parameters.single));
    bodies.add(IrFunction(function, [entry, normal, handler, ?again]));
  }

  final exports = <FunctionTarget, NativeExport>{};
  for (final (type, name) in [(node, 'plain'), (error, 'error')]) {
    final run = FunctionTarget(uri, name, .integer, [
      .integer,
      .integer,
      .integer,
    ]);
    final entry = Block(run.parameterTypes), normal = Block(), finish = Block();
    final handler = Block([.object, .stackTrace]);
    final original = entry.emit(
      Construct(constructors[type]!, [const Constant.integer(123)]),
    );
    entry.finish(
      Invoke(
        DirectCall(fresh, [original, ...entry.parameters]),
        onReturn: Jump(normal),
        onThrow: Jump(handler, [UnwindValue.exception, UnwindValue.stackTrace]),
      ),
    );
    normal.finish(Return(const Constant.integer(-1)));
    probe(handler, entry.parameters[1], entry.parameters[2]);
    handler.finish(
      Throw(
        handler.parameters.first,
        stackTrace: handler.parameters.last,
        onThrow: Jump(finish),
      ),
    );
    finish.finish(Return(finish.emit(LoadField(fields[type]!, original))));
    bodies.add(IrFunction(run, [entry, normal, handler, finish]));
    exports[run] = NativeExport(
      name,
      NativeSignature(Int64, [Int64, Int64, Int64]),
    );
  }

  final CodeGenerator generator = target.architecture == .arm64
      ? Arm64CodeGenerator(target)
      : X64CodeGenerator(target);
  final module = generator.generate(
    Compiler(generator.target).prepare(
      IrProgram(classes, bodies),
      runtime: heapRuntime,
      roots: bodies.map((f) => f.target),
      exports: exports,
    ),
  );
  return ObjectModule(
    target,
    module.sections,
    [
      for (final symbol in module.symbols)
        if (symbol.name == '.dartc.roots')
          Symbol(
            target.nativeSymbol('exception_roots'),
            symbol.section,
            symbol.offset,
            symbol.size,
            kind: .data,
            exported: true,
          )
        else
          symbol,
    ],
    imports: module.imports,
    relocations: module.relocations,
  );
}
