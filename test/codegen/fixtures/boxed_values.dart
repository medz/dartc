import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

import '../../support/runtime.dart';

ObjectModule boxedValues(Target target) {
  final library = Uri.parse('memory:boxed-values');
  final parameter = TypeParameterType('T')
    ..initializeBound(ValueType.object.nullable)
    ..initializeDefaultType(.dynamicType);
  final box = ClassType(library, 'Box', typeParameters: [parameter]);
  final item = InstanceField(box, 'item', parameter, isFinal: true);
  final read = FunctionTarget(
    library,
    'read',
    parameter,
    [],
    owner: box,
    kind: .getter,
  );
  final readBody = Block(read.parameterTypes);
  readBody.finish(
    Return(readBody.emit(LoadField(item, readBody.parameters.single))),
  );
  final functions = [
    IrFunction(read, [readBody]),
  ];
  final samples = <String, List<Constant>>{
    'integer': [
      const .integer(-0x8000000000000000),
      const .integer(0x7fffffffffffffff),
      const .integer(0),
    ],
    'floating': [
      const .floating(-0.0),
      for (final bits in [
        0x7ff8000000000001,
        0x7ff8000000000002,
        0xfff8000000000001,
        1,
      ])
        .floating((ByteData(8)..setUint64(0, bits)).getFloat64(0)),
      const .floating(double.infinity),
    ],
    'boolean': [const .boolean(false), const .boolean(true)],
  };
  for (final MapEntry(:key, :value) in samples.entries) {
    final type = value.first.type;
    final owner = box.instantiate([type]);
    final declaration = FunctionTarget(
      library,
      'generic_$key',
      type == .boolean ? .integer : type,
      [.integer],
    );
    final entry = Block(declaration.parameterTypes);
    final blocks = [entry];
    var next = entry;
    for (final (i, sample) in value.indexed) {
      final body = Block();
      blocks.add(body);
      if (i == value.length - 1) {
        next.finish(Jump(body));
      } else {
        final otherwise = Block();
        blocks.add(otherwise);
        next.finish(
          Branch(
            next.emit(Equals(entry.parameters.single, Constant.integer(i))),
            Jump(body),
            Jump(otherwise),
          ),
        );
        next = otherwise;
      }
      final instance = ObjectConstant(owner, {item: sample});
      final result = body.emit(
        i == 0
            ? LoadField(item, instance)
            : DirectCall(read, [instance], ownerType: owner),
      );
      if (type == .boolean) {
        final yes = Block()..finish(Return(const Constant.integer(1)));
        final no = Block()..finish(Return(const Constant.integer(0)));
        blocks.addAll([yes, no]);
        body.finish(Branch(result, Jump(yes), Jump(no)));
      } else {
        body.finish(Return(result));
      }
    }
    functions.add(IrFunction(declaration, blocks));
  }

  final rotate = FunctionTarget(
    library,
    'rotate',
    parameter,
    [...List.filled(9, parameter), ValueType.integer],
    owner: box,
    kind: .method,
  );
  final start = Block(rotate.parameterTypes),
      loop = Block([parameter, parameter, .integer]),
      again = Block(),
      done = Block();
  start.emit(DirectCall(read, [start.parameters.first]));
  start.finish(
    Jump(loop, [
      start.parameters[1],
      start.parameters[9],
      start.parameters[10],
    ]),
  );
  final left = loop.parameters[0],
      right = loop.parameters[1],
      count = loop.parameters[2];
  loop.finish(
    Branch(
      loop.emit(IntBinary(.greaterThan, count, const Constant.integer(0))),
      Jump(again),
      Jump(done),
    ),
  );
  again.emit(DirectCall(read, [start.parameters.first]));
  again.finish(
    Jump(loop, [
      right,
      left,
      again.emit(IntBinary(.subtract, count, const Constant.integer(1))),
    ]),
  );
  done.finish(Return(left));
  functions.add(IrFunction(rotate, [start, loop, again, done]));
  final doubles = box.instantiate([ValueType.floating]);
  final stack = FunctionTarget(library, 'boxed_stack', .floating, [.integer]);
  final stackBody = Block(stack.parameterTypes);
  stackBody.finish(
    Return(
      stackBody.emit(
        DirectCall(rotate, [
          ObjectConstant(doubles, {item: const .floating(7.5)}),
          for (var i = 0; i < 9; i++)
            Constant.floating(i == 8 ? -0.0 : i + 0.5),
          stackBody.parameters.single,
        ], ownerType: doubles),
      ),
    ),
  );
  functions.add(IrFunction(stack, [stackBody]));

  final booleans = box.instantiate([ValueType.boolean]);
  final runtimeBoolean = FunctionTarget(library, 'runtime_boolean', .integer, [
    .integer,
  ]);
  final boolBody = Block(runtimeBoolean.parameterTypes),
      yes = Block(),
      no = Block();
  final condition = boolBody.emit(
    IntBinary(
      .greaterThan,
      boolBody.parameters.single,
      const Constant.integer(0),
    ),
  );
  final boxedBoolean = boolBody.emit(
    DirectCall(rotate, [
      ObjectConstant(booleans, {item: const .boolean(false)}),
      ...List.filled(9, condition),
      const Constant.integer(1),
    ], ownerType: booleans),
  );
  boolBody.finish(Branch(boxedBoolean, Jump(yes), Jump(no)));
  yes.finish(Return(const Constant.integer(1)));
  no.finish(Return(const Constant.integer(0)));
  functions.add(IrFunction(runtimeBoolean, [boolBody, yes, no]));

  for (final operation in [
    'return',
    'view',
    'unchecked',
    'edge',
    'initial',
    'write',
  ]) {
    final factory = FunctionTarget(library, 'factory_$operation', .object, []);
    final body = Block(), join = Block([.object]);
    final blocks = [body];
    Value value = const Constant.integer(0);
    switch (operation) {
      case 'view':
        value = body.emit(TypeView(const Constant.floating(0.0), .object));
      case 'unchecked':
        value = body.emit(UncheckedCast(const Constant.floating(0.0), .object));
      case 'edge':
        body.finish(Jump(join, [const Constant.boolean(false)]));
        blocks.add(join);
        value = join.parameters.single;
      case 'initial' || 'write':
        final cell = body.emit(
          NewCell(CellType(.object), operation == 'initial' ? value : null),
        );
        if (operation == 'write') {
          body.emit(WriteCell(cell, const Constant.floating(0.0)));
        }
        value = body.emit(ReadCell(cell));
    }
    blocks.last.finish(Return(value));
    functions.add(IrFunction(factory, blocks));
    final check = FunctionTarget(library, 'box_$operation', .integer, []);
    final checkBody = Block(), yes = Block(), no = Block();
    final result = checkBody.emit(DirectCall(factory, []));
    checkBody.finish(
      Branch(
        checkBody.emit(Equals(result, const Constant.nullValue())),
        Jump(yes),
        Jump(no),
      ),
    );
    yes.finish(Return(const Constant.integer(1)));
    no.finish(Return(const Constant.integer(0)));
    functions.add(IrFunction(check, [checkBody, yes, no]));
  }

  final classes = [
    IrClass(box, [item], members: [read, rotate]),
  ];
  final voidBox = box.instantiate([ValueType.voidType]);
  final discard = FunctionTarget(library, 'discard_void', .integer, []);
  final discardBody = Block();
  discardBody.emit(
    DirectCall(read, [
      ObjectConstant(voidBox, {item: const .integer(42)}),
    ], ownerType: voidBox),
  );
  discardBody.finish(Return(const Constant.integer(7)));
  functions.add(IrFunction(discard, [discardBody]));
  for (final (name, sample) in [
    ('floating', const Constant.floating(-0.0)),
    ('integer', const Constant.integer(0x7fffffffffffffff)),
  ]) {
    final type = sample.type;
    final numeric = TypeParameterType('N')
      ..initializeBound(type)
      ..initializeDefaultType(type);
    final bound = ClassType(library, 'Bound$name', typeParameters: [numeric]);
    final applied = bound.instantiate([type]);
    final scalar = FunctionTarget(library, 'scalar_$name', type, [type]);
    final scalarBody = Block(scalar.parameterTypes);
    scalarBody.finish(Return(scalarBody.parameters.single));
    functions.add(IrFunction(scalar, [scalarBody]));
    final members = <FunctionTarget>[];
    for (final operation in [
      'return',
      'view',
      'unchecked',
      'edge',
      'initial',
      'write',
      'call',
    ]) {
      final method = FunctionTarget(
        library,
        operation,
        type,
        [numeric],
        owner: bound,
        kind: .method,
      );
      members.add(method);
      final body = Block(method.parameterTypes), join = Block([type]);
      final blocks = [body];
      Value value = body.parameters[1];
      switch (operation) {
        case 'view':
          value = body.emit(TypeView(value, type));
        case 'unchecked':
          value = body.emit(UncheckedCast(value, type));
        case 'edge':
          body.finish(Jump(join, [value]));
          blocks.add(join);
          value = join.parameters.single;
        case 'initial' || 'write':
          final cell = body.emit(
            NewCell(CellType(type), operation == 'initial' ? value : null),
          );
          if (operation == 'write') body.emit(WriteCell(cell, value));
          value = body.emit(ReadCell(cell));
        case 'call':
          value = body.emit(DirectCall(scalar, [value]));
      }
      blocks.last.finish(Return(value));
      functions.add(IrFunction(method, blocks));
      final wrapper = FunctionTarget(
        library,
        'unbox_${name}_$operation',
        type,
        [],
      );
      final call = Block();
      call.finish(
        Return(
          call.emit(
            DirectCall(method, [
              ObjectConstant(applied, {}),
              sample,
            ], ownerType: applied),
          ),
        ),
      );
      functions.add(IrFunction(wrapper, [call]));
    }
    classes.add(IrClass(bound, [], members: members));
  }
  for (final (name, sample) in <(String, Constant)>[
    ('integer', const .integer(7)),
    ('floating', const .floating(-0.0)),
  ]) {
    final type = sample.type;
    final fallback = type == .integer
        ? const Constant.integer(13)
        : const Constant.floating(13);
    final read = FunctionTarget(library, 'nullable_$name', type, [
      type.nullable,
    ]);
    final body = Block(read.parameterTypes), present = Block([type]);
    final absent = Block()..finish(Return(fallback));
    final test = body.emit(
      TypeTest(body.parameters.single, .nullType, negated: true),
    );
    body.finish(
      Branch(test, Jump(present, [test.refinement(true)!]), Jump(absent)),
    );
    present.finish(Return(present.parameters.single));
    functions.add(IrFunction(read, [body, present, absent]));

    final wrapper = FunctionTarget(library, 'refine_$name', type, [.integer]);
    final entry = Block(wrapper.parameterTypes), join = Block([type.nullable]);
    entry.finish(
      Branch(
        entry.emit(Equals(entry.parameters.single, const Constant.integer(0))),
        Jump(join, [sample]),
        Jump(join, [const Constant.nullValue()]),
      ),
    );
    final check = join.emit(TypeTest(join.parameters.single, type));
    final yes = Block([type, type.nullable]);
    final no = Block()..finish(Return(fallback));
    join.finish(
      Branch(
        check,
        Jump(yes, [check.refinement(true)!, check.refinement(true)!]),
        Jump(no),
      ),
    );
    final first = yes.emit(DirectCall(read, [yes.parameters[1]]));
    final second = yes.emit(DirectCall(read, [join.parameters.single]));
    Value sum = yes.parameters.first;
    for (final value in [first, second]) {
      sum = yes.emit(
        type == .integer
            ? IntBinary(.add, sum, value)
            : NumericBinary(.add, sum, value),
      );
    }
    yes.finish(Return(sum));
    functions.add(IrFunction(wrapper, [entry, join, yes, no]));
  }

  final pointerTest = FunctionTarget(library, 'pointer_test', .integer, [
    .integer,
  ]);
  final pointerBody = Block(pointerTest.parameterTypes);
  final pointer = pointerBody.emit(
    PointerFromAddress(
      pointerBody.parameters.single,
      FfiTypes.pointerTypes[Pointer<Int64>]!,
    ),
  );
  final isNull = Block()..finish(Return(const Constant.integer(1)));
  final notNull = Block()..finish(Return(const Constant.integer(0)));
  pointerBody.finish(
    Branch(
      pointerBody.emit(TypeTest(pointer, .nullType)),
      Jump(isNull),
      Jump(notNull),
    ),
  );
  functions.add(IrFunction(pointerTest, [pointerBody, isNull, notNull]));

  final markers = [for (var i = 0; i < 66; i++) ClassType(library, 'Marker$i')];
  final marked = ClassType(
    library,
    'Marked',
    interfaces: [markers[1], markers[63], markers[65]],
  );
  classes.addAll([
    for (final type in [...markers, marked]) IrClass(type, []),
  ]);
  final checks = FunctionTarget(library, 'type_words', .integer, [
    ValueType.object.nullable,
  ]);
  final checksEntry = Block(checks.parameterTypes);
  final checksBlocks = [checksEntry];
  var nextCheck = checksEntry;
  Value total = const Constant.integer(0);
  for (final (i, type) in markers.indexed) {
    final matched = Block(), join = Block([.integer]);
    nextCheck.finish(
      Branch(
        nextCheck.emit(TypeTest(checksEntry.parameters.single, type)),
        Jump(matched),
        Jump(join, [total]),
      ),
    );
    matched.finish(
      Jump(join, [
        matched.emit(IntBinary(.add, total, Constant.integer(i + 1))),
      ]),
    );
    checksBlocks.addAll([matched, join]);
    nextCheck = join;
    total = join.parameters.single;
  }
  nextCheck.finish(Return(total));
  functions.add(IrFunction(checks, checksBlocks));
  for (final (name, value) in <(String, Constant)>[
    ('marked_types', ObjectConstant(marked, {})),
    ('absent_types', const Constant.nullValue()),
  ]) {
    final run = FunctionTarget(library, name, .integer, []);
    final body = Block();
    body.finish(Return(body.emit(DirectCall(checks, [value]))));
    functions.add(IrFunction(run, [body]));
  }

  final program = IrProgram(classes, functions);
  final CodeGenerator generator = target.architecture == .arm64
      ? Arm64CodeGenerator(target)
      : X64CodeGenerator(target);
  return generator.generate(
    program,
    runtime: heapRuntime,
    definitions: functions.map((f) => f.target),
    exports: {
      for (final f in functions)
        if (f.target.kind == .function &&
            f.target.parameterTypes.every((type) => type == .integer) &&
            (f.target.returnType == .integer ||
                f.target.returnType == .floating))
          f.target: NativeExport(
            f.target.name,
            NativeSignature(
              f.target.returnType == .floating ? Double : Int64,
              List.filled(f.target.parameterTypes.length, Int64),
            ),
          ),
    },
  );
}
