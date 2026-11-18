import 'package:dartc/abi.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/instance_storage.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/storage_access.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  final uri = Uri.parse('memory:instance-storage');
  test(
    'late cell copies preserve raw binding state without reading the value',
    () {
      final target = FunctionTarget(uri, 'copy', .voidType, []);
      final type = CellType(.integer, isLate: true);
      final entry = Block([]), done = Block([type]), failed = Block();
      final cell = NewCell(type, null);
      entry.finish(
        Invoke(cell, onReturn: Jump(done, [cell]), onThrow: Jump(failed)),
      );
      done.emit(CopyCell(done.parameters.single));
      done.finish(const Return());
      failed.finish(const Return());
      final function = IrFunction(target, [entry, done, failed]);
      final source = IrProgram([], [function]);
      final program = CellLowering().bind().normalize(source);
      final shape = program.classes.map((c) => c.cellStorage).nonNulls.single;
      final body = program.implementationOf(target)! as IrFunction;
      final reads = body.blocks
          .expand((block) => block.instructions)
          .whereType<LoadField>()
          .toList();
      expect(reads.map((read) => read.field), shape.fields);
      expect(reads.map((read) => read.receiver).toSet(), hasLength(1));
      expect(body.callees, {shape.initializer});
      final layouts = ProgramLayout(
        program.classes,
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
        executionShapes: program.executionShapes,
      );
      expect(
        layouts.storageOf(shape.type).layout.referenceOffsets,
        contains(layouts.fieldOffset(shape.thunk!)),
      );
      final failedBlock = body.blocks.singleWhere(
        (block) =>
            block.end is Return &&
            block.instructions.isEmpty &&
            body.blocks.any(
              (previous) =>
                  previous.end is Invoke &&
                  identical((previous.end as Invoke).onThrow.target, block),
            ),
      );
      expect(body.blocks.where((block) => block.end is Invoke), isNotEmpty);
      expect((body.entry.end as Invoke).onThrow.target, same(failedBlock));
    },
  );

  test('late aliases share one value slot and inherited binding identity', () {
    final owner = ClassType(uri, 'Base');
    final child = ClassType(uri, 'Child', superclass: owner);
    final value = InstanceField(owner, 'value', .object.nullable, isLate: true);
    final number = InstanceField(child, 'number', .integer, isLate: true);
    final layouts = ProgramLayout([
      IrClass(owner, [value]),
      IrClass(child, [number]),
    ], nativeLayout: NativeLayout(const Target(.linux, .arm64)));
    final (backing, bound) = layouts.instances.slots(value);
    final storage = layouts.storageOf(child);
    expect(storage.fields, [
      backing,
      bound,
      ...[
        layouts.instances.slots(number).$1,
        layouts.instances.slots(number).$2,
      ],
    ]);
    expect(storage.layout.size, ObjectHeader.fieldsOffset + 32);
    expect(storage.layout.referenceOffsets, [
      ObjectHeader.typeOffset,
      ObjectHeader.fieldsOffset,
    ]);
    expect(layouts.fieldOffset(value), layouts.fieldOffset(backing));
    expect(storage.offsetOf(bound), layouts.storageOf(owner).offsetOf(bound));
    expect(layouts.instances.slots(value).$1, same(backing));
    expect(backing.isLate, isFalse);
    expect(bound.type, ValueType.boolean);
  });

  test(
    'generic final writes check type before binding and preserve handlers',
    () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final owner = ClassType(uri, 'Box', typeParameters: [t]);
      final field = InstanceField(
        owner,
        'value',
        t,
        isLate: true,
        isFinal: true,
      );
      final target = FunctionTarget(
        uri,
        'write',
        .voidType,
        [t],
        owner: owner,
        kind: .method,
      );
      final entry = Block(target.parameterTypes),
          done = Block(),
          failed = Block();
      final store = StoreField(field, entry.parameters[0], entry.parameters[1]);
      entry.finish(Invoke(store, onReturn: Jump(done), onThrow: Jump(failed)));
      done.finish(const Return());
      failed.finish(const Return());
      final function = IrFunction(target, [entry, done, failed]);
      final error = ClassType(
        Uri.parse('dart:_internal'),
        'LateError',
        superclass: ValueType.error,
      );
      final constructor = FunctionTarget(
        error.library,
        'new',
        .voidType,
        [.string],
        owner: error,
        kind: .initializer,
      );
      final constructed = Block(constructor.parameterTypes)
        ..finish(const Return());
      final storage = InstanceStorage([
        function,
      ], lateError: IrFunction(constructor, [constructed]));
      final layouts = ProgramLayout(
        [
          IrClass(owner, [field], members: [target]),
        ],
        instanceStorage: storage,
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      );
      final body = FunctionRepresentation(
        function,
        layouts,
        CheckedCasts(failure: heapRuntime.typeCheckFailure),
        MemberCalls(IrProgram([], []), {}),
        HeapPlan(),
      );
      var block = entry;
      final operations = <Value>[];
      while (body.ends[block] is Invoke) {
        operations.addAll(body.instructions[block]!);
        final invoke = body.ends[block] as Invoke;
        expect(invoke.onThrow.target, same(failed));
        block = invoke.onReturn!.target;
      }
      operations.addAll(body.instructions[block]!);
      expect(body.ends[block], isA<Branch>());
      final check = operations.whereType<TypeCast>().singleWhere(
        (cast) => cast.type == t,
      );
      final bound = operations.whereType<StorageRead>().singleWhere(
        (load) => load.field == storage.slots(field).$2,
      );
      expect(operations.indexOf(check), lessThan(operations.indexOf(bound)));
      expect(body.aliases, contains(store));
      final failure = body.ends.values.whereType<Invoke>().singleWhere(
        (invoke) =>
            invoke.operation is DirectCall &&
            (invoke.operation as DirectCall).target == storage.failure!.target,
      );
      expect(failure.onThrow.target, same(failed));
      expect(failure.onReturn, isNull);
    },
  );

  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final CodeGenerator generator = arch == .arm64
          ? Arm64CodeGenerator(target)
          : X64CodeGenerator(target);
      test('$target mutable initialized instance late needs no LateError', () {
        final owner = ClassType(uri, 'Cell');
        final initialize = FunctionTarget(
          uri,
          'initialize',
          .integer,
          [],
          owner: owner,
          kind: .fieldInitializer,
        );
        final value = InstanceField(
          owner,
          'value',
          .integer,
          isLate: true,
          initializer: initialize,
        );
        final initial = Block(initialize.parameterTypes)
          ..finish(Return(const Constant.integer(7)));
        final read = FunctionTarget(uri, 'read', .integer, [owner]);
        final entry = Block(read.parameterTypes);
        entry.finish(
          Return(entry.emit(LoadField(value, entry.parameters.single))),
        );
        final program = IrProgram(
          [
            IrClass(owner, [value]),
          ],
          [
            IrFunction(initialize, [initial]),
            IrFunction(read, [entry]),
          ],
        );
        expect(
          generator
              .generate(
                Compiler(generator.target)
                    .prepare(program, runtime: heapRuntime, roots: [read]),
              )
              .sections,
          isNotEmpty,
        );
      });
    }
  }
}
