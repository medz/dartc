import 'dart:ffi';

import 'package:dartc/compiler.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

import '../../support/runtime.dart';

ObjectModule dynamicBoxes(Target target) {
  final uri = Uri.parse('memory:dynamic-boxes');
  final holder = ClassType(uri, 'Holder');
  final fields = [
    InstanceField(holder, 'integer', ValueType.integer.nullable),
    InstanceField(holder, 'floating', ValueType.floating.nullable),
  ];
  final ctor = FunctionTarget(
    uri,
    'Holder',
    .voidType,
    fields.map((field) => field.type),
    owner: holder,
    kind: .initializer,
  );
  final init = Block(ctor.parameterTypes);
  for (final (i, field) in fields.indexed) {
    init.emit(StoreField(field, init.parameters.first, init.parameters[i + 1]));
  }
  init.finish(const Return());
  final functions = <IrFunction>[
    IrFunction(ctor, [init]),
  ];
  final parameter = TypeParameterType('T')
    ..initializeBound(ValueType.object.nullable)
    ..initializeDefaultType(.dynamicType);
  final generic = ClassType(uri, 'Generic', typeParameters: [parameter]);
  final identity = FunctionTarget(
    uri,
    'identity',
    parameter,
    [parameter],
    owner: generic,
    kind: .method,
  );
  final identityBody = Block(identity.parameterTypes);
  identityBody.finish(Return(identityBody.parameters.last));
  functions.add(IrFunction(identity, [identityBody]));
  final classes = [
    IrClass(holder, fields, constructors: [ctor]),
    IrClass(generic, [], members: [identity]),
  ];
  final burn = FunctionTarget(uri, 'burn', .voidType, [.integer]);
  final exports = <FunctionTarget, NativeExport>{};
  for (final type in <ValueType>[.integer, .floating]) {
    final name = type == .integer ? 'integer' : 'floating';
    final bounded = TypeParameterType('N')
      ..initializeBound(type)
      ..initializeDefaultType(type);
    final container = ClassType(uri, 'Scalar_$name', typeParameters: [bounded]);
    final field = InstanceField(container, 'value', type, isFinal: true);
    final scalarCtor = FunctionTarget(
      uri,
      '',
      .voidType,
      List.filled(10, bounded),
      owner: container,
      kind: .initializer,
    );
    final initialize = Block(scalarCtor.parameterTypes);
    initialize.emit(DirectCall(burn, [const Constant.integer(4096)]));
    initialize.emit(
      StoreField(
        field,
        initialize.parameters.first,
        initialize.emit(TypeView(initialize.parameters.last, type)),
      ),
    );
    initialize.finish(const Return());
    functions.add(IrFunction(scalarCtor, [initialize]));
    classes.add(IrClass(container, [field], constructors: [scalarCtor]));
    final accept = FunctionTarget(uri, 'accept_$name', type.nullable, [
      type.nullable,
    ]);
    final acceptBody = Block(accept.parameterTypes);
    acceptBody.finish(Return(acceptBody.parameters.single));
    functions.add(IrFunction(accept, [acceptBody]));
    for (final operation in [
      'return',
      'call',
      'edge',
      'view',
      'initial',
      'write',
      'field',
      'construct',
      'generic',
      'generic_construct',
    ]) {
      final factory = FunctionTarget(uri, '${name}_$operation', type.nullable, [
        type,
      ]);
      final body = Block(factory.parameterTypes), join = Block([type.nullable]);
      final blocks = [body], value = body.parameters.single;
      Value result = value;
      switch (operation) {
        case 'call':
          result = body.emit(DirectCall(accept, [value]));
        case 'edge':
          body.finish(Jump(join, [value]));
          blocks.add(join);
          result = join.parameters.single;
        case 'view':
          result = body.emit(TypeView(value, type.nullable));
        case 'initial' || 'write':
          final cell = body.emit(
            NewCell(
              CellType(type.nullable),
              operation == 'initial' ? value : const Constant.nullValue(),
            ),
          );
          if (operation == 'write') body.emit(WriteCell(cell, value));
          result = body.emit(ReadCell(cell));
        case 'field' || 'construct':
          final object = body.emit(
            Construct(ctor, [
              for (final field in fields)
                operation == 'construct' && field.type == type.nullable
                    ? value
                    : const Constant.nullValue(),
            ]),
          );
          final field = fields[type == .integer ? 0 : 1];
          if (operation == 'field') body.emit(StoreField(field, object, value));
          result = body.emit(LoadField(field, object));
        case 'generic':
          final receiver = generic.instantiate([type]);
          result = body.emit(
            DirectCall(identity, [
              ObjectConstant(receiver, {}),
              value,
            ], ownerType: receiver),
          );
        case 'generic_construct':
          final object = body.emit(
            Construct(scalarCtor, [
              for (var i = 0; i < 9; i++)
                type == .integer
                    ? Constant.integer(i)
                    : Constant.floating(i.toDouble()),
              value,
            ], instantiatedType: container.instantiate([type])),
          );
          result = body.emit(LoadField(field, object));
      }
      blocks.last.finish(Return(result));
      functions.add(IrFunction(factory, blocks));
      final wrapper = FunctionTarget(uri, 'read_${name}_$operation', type, [
        type,
      ]);
      final entry = Block(wrapper.parameterTypes),
          yes = Block([type]),
          no = Block();
      final boxed = entry.emit(DirectCall(factory, entry.parameters));
      final test = entry.emit(TypeTest(boxed, type));
      entry.finish(Branch(test, Jump(yes, [test.refinement(true)!]), Jump(no)));
      yes.finish(Return(yes.parameters.single));
      no.finish(
        Return(
          type == .integer
              ? const Constant.integer(-1)
              : const Constant.floating(-1),
        ),
      );
      functions.add(IrFunction(wrapper, [entry, yes, no]));
      exports[wrapper] = NativeExport(
        wrapper.name,
        NativeSignature(type == .integer ? Int64 : Double, [
          type == .integer ? Int64 : Double,
        ]),
      );
    }
  }

  final start = Block(burn.parameterTypes),
      loop = Block([.integer]),
      allocate = Block(),
      done = Block();
  start.finish(Jump(loop, [const Constant.integer(0)]));
  final index = loop.parameters.single;
  loop.finish(
    Branch(
      loop.emit(IntBinary(.lessThan, index, start.parameters.single)),
      Jump(allocate),
      Jump(done),
    ),
  );
  allocate.emit(TypeView(index, .object));
  allocate.finish(
    Jump(loop, [
      allocate.emit(IntBinary(.add, index, const Constant.integer(1))),
    ]),
  );
  done.finish(const Return());
  functions.add(IrFunction(burn, [start, loop, allocate, done]));

  final sum = FunctionTarget(uri, 'sum', .integer, [
    ...List.filled(10, ValueType.integer.nullable),
    ValueType.integer,
  ]);
  final sumEntry = Block(sum.parameterTypes), invalid = Block();
  sumEntry.emit(DirectCall(burn, [sumEntry.parameters.last]));
  final sumBlocks = [sumEntry, invalid];
  var current = sumEntry;
  Value total = const Constant.integer(0);
  for (final parameter in sumEntry.parameters.take(10)) {
    final next = Block([.integer]);
    sumBlocks.add(next);
    final test = current.emit(TypeTest(parameter, .integer));
    current.finish(
      Branch(test, Jump(next, [test.refinement(true)!]), Jump(invalid)),
    );
    total = next.emit(IntBinary(.add, total, next.parameters.single));
    current = next;
  }
  current.finish(Return(total));
  invalid.finish(Return(const Constant.integer(-1)));
  functions.add(IrFunction(sum, sumBlocks));
  final run = FunctionTarget(uri, 'gc_arguments', .integer, [
    .integer,
    .integer,
  ]);
  final entry = Block(run.parameterTypes);
  entry.emit(DirectCall(burn, [entry.parameters.last]));
  final arguments = [
    for (var i = 0; i < 10; i++)
      entry.emit(IntBinary(.add, entry.parameters.first, Constant.integer(i))),
  ];
  entry.finish(
    Return(entry.emit(DirectCall(sum, [...arguments, entry.parameters.last]))),
  );
  functions.add(IrFunction(run, [entry]));
  exports[run] = NativeExport(run.name, NativeSignature(Int64, [Int64, Int64]));

  final element = TypeParameterType('T')
    ..initializeBound(ValueType.object.nullable);
  final slot = ClassType(uri, 'Slot', typeParameters: [element]);
  final item = InstanceField(slot, 'item', element);
  final slotInit = FunctionTarget(
    uri,
    'Slot',
    .voidType,
    [element],
    owner: slot,
    kind: .initializer,
  );
  final initialized = Block(slotInit.parameterTypes);
  initialized.emit(
    StoreField(item, initialized.parameters[0], initialized.parameters[1]),
  );
  initialized.finish(const Return());
  functions.add(IrFunction(slotInit, [initialized]));
  final replace = FunctionTarget(
    uri,
    'replace',
    .integer,
    [slot, element],
    owner: slot,
    kind: .method,
  );
  final replacing = Block(replace.parameterTypes),
      written = Block(),
      failed = Block([.object]),
      rejected = Block(),
      unexpected = Block();
  replacing.emit(DirectCall(burn, [const Constant.integer(10000)]));
  replacing.finish(
    Invoke(
      StoreField(item, replacing.parameters[1], replacing.parameters[2]),
      onReturn: Jump(written),
      onThrow: Jump(failed, [UnwindValue.exception]),
    ),
  );
  written.finish(Return(const Constant.integer(1)));
  failed.finish(
    Branch(
      failed.emit(TypeTest(failed.parameters.single, .typeError)),
      Jump(rejected),
      Jump(unexpected),
    ),
  );
  rejected.finish(Return(const Constant.integer(2)));
  unexpected.finish(Return(const Constant.integer(3)));
  functions.add(
    IrFunction(replace, [replacing, written, failed, rejected, unexpected]),
  );
  classes.add(
    IrClass(slot, [item], constructors: [slotInit], members: [replace]),
  );

  for (final type in <ValueType>[.integer, .floating]) {
    final name = type == .integer ? 'integer' : 'floating';
    final wrapper = FunctionTarget(uri, 'checked_$name', type, [type]);
    final entry = Block(wrapper.parameterTypes),
        correct = Block(),
        wrong = Block();
    final value = entry.parameters.single;
    final object = entry.emit(
      Construct(slotInit, [value], instantiatedType: slot.instantiate([type])),
    );
    final wide = slot.instantiate([ValueType.number]);
    final receiver = entry.emit(
      Construct(slotInit, [const Constant.integer(0)], instantiatedType: wide),
    );
    final result = entry.emit(
      DirectCall(replace, [
        receiver,
        object,
        type == .integer ? const Constant.floating(0.5) : value,
      ], ownerType: wide),
    );
    entry.finish(
      Branch(
        entry.emit(Equals(result, Constant.integer(type == .integer ? 2 : 1))),
        Jump(correct),
        Jump(wrong),
      ),
    );
    correct.emit(DirectCall(burn, [const Constant.integer(10000)]));
    correct.finish(Return(correct.emit(LoadField(item, object))));
    wrong.finish(
      Return(
        type == .integer
            ? const Constant.integer(-999)
            : const Constant.floating(-999),
      ),
    );
    functions.add(IrFunction(wrapper, [entry, correct, wrong]));
    exports[wrapper] = NativeExport(
      wrapper.name,
      NativeSignature(type == .integer ? Int64 : Double, [
        type == .integer ? Int64 : Double,
      ]),
    );
  }

  final program = IrProgram(classes, functions);
  final CodeGenerator generator = target.architecture == .arm64
      ? Arm64CodeGenerator(target)
      : X64CodeGenerator(target);
  return generator.generate(
    Compiler(generator.target).prepare(
      program,
      runtime: heapRuntime,
      roots: functions.map((f) => f.target),
      exports: exports,
    ),
  );
}
