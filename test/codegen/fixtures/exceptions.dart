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
  final box = ClassType(uri, 'Box');
  final error = ClassType(uri, 'Failure', superclass: ValueType.error);
  final classes = <IrClass>[
    IrClass(
      ValueType.error,
      heapRuntime.program.classes
          .singleWhere((declaration) => declaration.type == ValueType.error)
          .fields,
    ),
  ];
  final bodies = <IrFunction>[];
  final constructors = <ClassType, FunctionTarget>{};
  final fields = <ClassType, InstanceField>{};
  for (final type in [node, error, box]) {
    final content = type == box ? node : ValueType.integer;
    final field = fields[type] = InstanceField(type, 'value', content);
    final ctor = constructors[type] = FunctionTarget(
      uri,
      type.name,
      .voidType,
      [content],
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

  final local = FunctionTarget(uri, 'localCaught', node, [box, .stackTrace]);
  final localEntry = Block(local.parameterTypes),
      localHandler = Block([ValueType.object]);
  final loaded = localEntry.emit(
    LoadField(fields[box]!, localEntry.parameters.first),
  );
  localEntry.finish(
    Throw(
      loaded,
      stackTrace: localEntry.parameters.last,
      onThrow: Jump(localHandler, [UnwindValue.exception]),
    ),
  );
  localHandler.emit(KeepAlive(localEntry.parameters.first));
  localHandler.finish(
    Return(
      localHandler.emit(UncheckedCast(localHandler.parameters.single, node)),
    ),
  );
  bodies.add(IrFunction(local, [localEntry, localHandler]));

  final runLocal = FunctionTarget(uri, 'local', .integer, []);
  final localStart = Block(), captured = Block([.stackTrace]);
  final original = localStart.emit(
    Construct(constructors[node]!, [const Constant.integer(321)]),
  );
  final container = localStart.emit(Construct(constructors[box]!, [original]));
  localStart.finish(
    Invoke(
      DirectCall(thrower, [original]),
      onReturn: null,
      onThrow: Jump(captured, [UnwindValue.stackTrace]),
    ),
  );
  final caught = captured.emit(
    DirectCall(local, [container, captured.parameters.single]),
  );
  captured.finish(Return(captured.emit(LoadField(fields[node]!, caught))));
  bodies.add(IrFunction(runLocal, [localStart, captured]));
  exports[runLocal] = NativeExport('local', NativeSignature(Int64, []));

  final checkedTrace = FunctionTarget(uri, 'checkedTrace', .boolean, []);
  final checkedEntry = Block(), accepted = Block();
  final failed = Block([.object, .stackTrace]);
  checkedEntry.finish(
    Invoke(
      TypeCast(const Constant.string('invalid'), .integer),
      onReturn: Jump(accepted),
      onThrow: Jump(failed, [UnwindValue.exception, UnwindValue.stackTrace]),
    ),
  );
  accepted.finish(const Return(Constant.boolean(false)));
  final traceField = classes.first.fields.singleWhere(
    (field) => field.name == '_stackTrace',
  );
  final failure = failed.emit(UncheckedCast(failed.parameters.first, .error));
  failed.finish(
    Return(
      failed.emit(
        Identical(
          failed.emit(LoadField(traceField, failure)),
          failed.parameters.last,
        ),
      ),
    ),
  );
  bodies.add(IrFunction(checkedTrace, [checkedEntry, accepted, failed]));
  exports[checkedTrace] = NativeExport(
    'checkedTrace',
    NativeSignature(Bool, []),
  );

  final exhaustion = FunctionTarget(uri, 'exhaustion', .boolean, []);
  final report = Block(), first = Block([.object, .stackTrace]);
  final second = Block([.object, .stackTrace]);
  final classified = Block(), traced = Block(), incorrect = Block();
  for (final (from, handler) in [(report, first), (first, second)]) {
    from.finish(
      Invoke(
        DirectCall(heapRuntime.allocationFailure!, []),
        onReturn: null,
        onThrow: Jump(handler, [UnwindValue.exception, UnwindValue.stackTrace]),
      ),
    );
  }
  second.finish(
    Branch(
      second.emit(Identical(first.parameters.first, second.parameters.first)),
      Jump(classified),
      Jump(incorrect),
    ),
  );
  classified.finish(
    Branch(
      classified.emit(
        DirectCall(heapRuntime.isOutOfMemory, [second.parameters.first]),
      ),
      Jump(traced),
      Jump(incorrect),
    ),
  );
  traced.finish(
    Return(
      traced.emit(Identical(first.parameters.last, second.parameters.last)),
    ),
  );
  incorrect.finish(const Return(Constant.boolean(false)));
  bodies.add(
    IrFunction(exhaustion, [
      report,
      first,
      second,
      classified,
      traced,
      incorrect,
    ]),
  );
  exports[exhaustion] = NativeExport('exhaustion', NativeSignature(Bool, []));

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
