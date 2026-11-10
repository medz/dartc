import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

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
  final exports = <FunctionTarget, NativeExport>{};
  for (final type in <ValueType>[.integer, .floating]) {
    final name = type == .integer ? 'integer' : 'floating';
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

  final burn = FunctionTarget(uri, 'burn', .voidType, [.integer]);
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

  final program = IrProgram([
    IrClass(holder, fields, constructors: [ctor]),
    IrClass(generic, [], members: [identity]),
  ], functions);
  final CodeGenerator generator = target.architecture == .arm64
      ? Arm64CodeGenerator(target)
      : X64CodeGenerator(target);
  return generator.generate(
    program,
    definitions: functions.map((f) => f.target),
    exports: exports,
  );
}
