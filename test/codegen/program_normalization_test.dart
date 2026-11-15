import 'dart:typed_data';

import 'package:dartc/codegen.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/codegen/constant_data.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  late IrProgram runtimeProgram;
  setUpAll(() async {
    await prepareRuntime();
    runtimeProgram = ProgramNormalization(
      heapRuntime.program,
      runtime: heapRuntime,
    ).run();
  });
  IrProgram normalize(IrFunction body) => ProgramNormalization(
    IrProgram(
      runtimeProgram.classes,
      [...runtimeProgram.functions, body],
      globals: runtimeProgram.globals,
      externals: runtimeProgram.externals,
    ),
    runtime: heapRuntime,
  ).run();

  test('semantic Type values do not assume their future storage class', () {
    for (final view in [ValueType.typeType, ValueType.object]) {
      final target = FunctionTarget(null, 'typeEquals', .boolean, [.typeType]);
      final entry = Block(target.parameterTypes);
      final type = entry.emit(TypeView(entry.parameters.single, view));
      entry.finish(Return(entry.emit(Equals(type, TypeConstant(.integer)))));
      final program = normalize(IrFunction(target, [entry]));
      final facts = ProgramFlow(program, [], openEntries: [target]).facts;
      expect(facts.returnedBy(target).constant, isNull);
      expect(facts.returnedBy(target).unknownTypes, {ValueType.boolean});
    }
  });

  test('nested constants and defaults share the emitted object storage', () {
    final list = SequenceConstant(CoreTypes.listOf(.integer), [
      const Constant.integer(7),
      const Constant.integer(9),
    ]);
    final type = RecordType([list.type], {});
    final value = RecordConstant(type, [list]);
    final root = FunctionTarget(null, 'constant', type, [
      type,
    ], optionalPositional: 1);
    final imported = FunctionTarget(null, 'imported', type, [
      type,
    ], optionalPositional: 1);
    final body = IrFunction(
      root,
      [Block(root.parameterTypes)..finish(Return(value))],
      defaults: {0: value},
    );
    final whole = ProgramNormalization(
      IrProgram(
        runtimeProgram.classes,
        [...runtimeProgram.functions, body],
        globals: runtimeProgram.globals,
        externals: [
          ...runtimeProgram.externals,
          IrExternal(imported, defaults: {0: value}),
        ],
      ),
      runtime: heapRuntime,
    ).run();
    final normalized = whole.implementationOf(root) as IrFunction;
    final record = (normalized.entry.end as Return).value as RecordConstant;
    final object = record.fields.single as ObjectConstant;
    expect(object.type, isNot(list.type));
    expect(list.type.accepts(object.type), isTrue);
    final stored = whole.classes
        .singleWhere((c) => c.type == (object.type as ClassType).declaration)
        .listStorage!;
    final payload = object.fields[stored.data] as ObjectConstant;
    expect(payload.payload.map((value) => (value as ScalarConstant).value), [
      7,
      9,
    ]);
    expect(normalized.defaults[0]!.structuralKey, record.structuralKey);
    expect(
      whole.implementationOf(imported)!.defaults[0]!.structuralKey,
      record.structuralKey,
    );
    expect(
      ProgramNormalization(whole, runtime: heapRuntime).run(),
      same(whole),
    );

    final layouts = ProgramLayout(
      whole.classes,
      nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      typeRuntime: heapRuntime.types,
    );
    final data = ConstantData(layouts, 0);
    final first = data.addressOf(object);
    final repeated = ((normalized.defaults[0] as RecordConstant).fields.single);
    expect(data.addressOf(repeated), first);
    final offset = data.symbols[first].offset;
    final storage = layouts.storageOf(object.type as ClassType);
    final relocation = data.relocations.singleWhere(
      (entry) => entry.offset == offset + storage.offsetOf(stored.data),
    );
    final buffer = data.symbols[relocation.symbol];
    final bytes = ByteData.sublistView(data.finish().bytes);
    expect(
      bytes.getInt64(offset + storage.offsetOf(stored.length), .little),
      2,
    );
    expect(
      buffer.size,
      layouts.objectLayout(payload.type as ClassType).size + 16,
    );
    for (final (index, expected) in [7, 9].indexed) {
      final slot = buffer.offset + ObjectHeader.fieldsOffset + index * 8;
      final reference = data.relocations.singleWhere(
        (entry) => entry.offset == slot,
      );
      final scalar = data.symbols[reference.symbol];
      expect(
        bytes.getInt64(scalar.offset + ObjectHeader.fieldsOffset, .little),
        expected,
      );
    }
  });

  test(
    'collection construction exposes checked factories and actual arguments',
    () {
      final root = FunctionTarget(null, 'collections', .voidType, []);
      final block = Block();
      block.emit(NewCollection(CoreTypes.listOf(.integer)));
      block.emit(
        NewCollection(
          CoreTypes.listOf(.integer),
          growable: const Constant.boolean(false),
        ),
      );
      block.emit(NewCollection(CoreTypes.mapOf(.string, .integer)));
      block.emit(NewCollection(CoreTypes.setOf(.integer)));
      final filled = block.emit(
        ListFilled(
          CoreTypes.listOf(.integer),
          const Constant.integer(3),
          const Constant.integer(7),
          const Constant.boolean(false),
        ),
      );
      block.emit(
        ListFrom(
          CoreTypes.listOf(.integer),
          filled,
          const Constant.boolean(true),
        ),
      );
      block.finish(const Return());
      final whole = normalize(IrFunction(root, [block]));
      final normalized = whole.implementationOf(root) as IrFunction;
      final calls = normalized.entry.instructions
          .whereType<DirectCall>()
          .toList();
      expect(calls, hasLength(6));
      for (final (index, call) in calls.indexed) {
        expect(
          heapRuntime.program.implementationOf(call.target),
          isA<IrFunction>(),
        );
        expect(
          call.ownerType!.typeArguments,
          index == 2 ? <ValueType>[.string, .integer] : <ValueType>[.integer],
        );
      }
      expect(
        calls[0].inputs.single,
        isA<ScalarConstant>().having((v) => v.value, 'growable', true),
      );
      expect(
        calls[1].inputs.single,
        isA<ScalarConstant>().having((v) => v.value, 'growable', false),
      );
      expect(calls[4].inputs.map((v) => (v as ScalarConstant).value), [
        3,
        7,
        false,
      ]);
      expect(calls[5].inputs.first, same(calls[4]));
      expect((calls[5].inputs.last as ScalarConstant).value, true);
      expect(
        ProgramNormalization(whole, runtime: heapRuntime).run(),
        same(whole),
      );
    },
  );

  test(
    'generic construction and literal spread retain lexical type arguments',
    () {
      final element = TypeParameterType('E')..initializeBound(.object.nullable);
      final list = CoreTypes.listOf(element);
      final root = FunctionTarget(
        null,
        'spread',
        list,
        [CoreTypes.iterableOf(.object.nullable)],
        typeParameters: [element],
      );
      final block = Block(root.parameterTypes),
          normal = Block([list]),
          caught = Block();
      final value = block.emit(NewCollection(list));
      final spread = CollectionSpread(value, block.parameters.single);
      block.finish(
        Invoke(spread, onReturn: Jump(normal, [value]), onThrow: Jump(caught)),
      );
      normal.finish(Return(normal.parameters.single));
      caught.finish(Throw(const Constant.integer(73)));
      final normalized = normalize(
        IrFunction(root, [block, normal, caught]),
      ).implementationOf(root) as IrFunction;
      final creation = normalized.entry.instructions.single as DirectCall;
      expect(creation.ownerType!.typeArguments, [element]);
      final invocation = normalized.entry.end as Invoke;
      final call = invocation.operation as DirectCall;
      expect(call.typeArguments, [element]);
      expect(call.inputs.first, same(creation));
      expect(invocation.onThrow.target.end, isA<Throw>());
      expect(invocation.onReturn!.target.end, isA<Return>());
    },
  );

  test('unchanged external defaults do not create a new program version', () {
    final type = CoreTypes.setOf(.integer);
    final entry = FunctionTarget(null, 'external', type, [
      type,
    ], optionalPositional: 1);
    final source = IrProgram(
      [],
      [],
      externals: [
        IrExternal(
          entry,
          defaults: {
            0: SequenceConstant(type, [const Constant.integer(7)]),
          },
        ),
      ],
    );
    expect(ProgramNormalization(source).run(), same(source));
  });

  test('missing checked constructors fail before machine representation', () {
    final root = FunctionTarget(
      null,
      'missing',
      CoreTypes.listOf(.integer),
      [],
    );
    final block = Block();
    block.finish(Return(block.emit(NewCollection(CoreTypes.listOf(.integer)))));
    final program = IrProgram([], [
      IrFunction(root, [block]),
    ]);
    expect(() => ProgramNormalization(program).run(), throwsArgumentError);
  });
}
