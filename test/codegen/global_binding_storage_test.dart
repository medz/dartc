import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/src/codegen/constant_data.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:binding-storage');
  final type = ValueType.boolean.nullable;
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

  ({ModuleObject module, ProgramLayout layouts, IrFunction get, IrFunction set})
  accessors(GlobalVariable global) {
    final target = FunctionTarget(uri, 'replace', type, [type]);
    final entry = Block(target.parameterTypes);
    final read = LoadGlobal(global);
    final write = StoreGlobal(global, entry.parameters.single);
    entry.emit(read);
    entry.emit(write);
    entry.finish(Return(read));
    final program = IrProgram(
      [
        IrClass(error, [], constructors: [constructor]),
      ],
      [
        IrFunction(target, [entry]),
        IrFunction(constructor, [
          Block(constructor.parameterTypes)..finish(const Return()),
        ]),
        if (global.initializer case final init?)
          IrFunction(init, [
            Block()..finish(const Return(Constant.nullValue())),
          ]),
      ],
      globals: [global],
    );
    final lowered = GlobalLowering(
      lateError: program.implementationOf(constructor),
    ).lower(program, [target]);
    final replacement = lowered.implementationOf(target) as IrFunction;
    final calls = replacement.entry.instructions
        .whereType<DirectCall>()
        .toList();
    final get = lowered.implementationOf(calls.first.target) as IrFunction;
    final set = lowered.implementationOf(calls.last.target) as IrFunction;
    final module = {...get.moduleObjects, ...set.moduleObjects}.single;
    final layouts = ProgramLayout(
      lowered.classes,
      nativeLayout: NativeLayout(const Target(.macos, .arm64)),
    );
    return (module: module, layouts: layouts, get: get, set: set);
  }

  test('implicitly null globals need only one traced slot and one store', () {
    final (:module, :layouts, :get, :set) = accessors(
      GlobalVariable(uri, 'flag', type),
    );
    final holder = layouts.storageOf(module.type);
    expect(
      holder.layout.size,
      ObjectHeader.fieldsOffset + ObjectHeader.alignment,
    );
    final field = holder.fields.single;
    expect(holder.layout.referenceOffsets, [
      ObjectHeader.typeOffset,
      holder.offsetOf(field),
    ]);
    final bytes = ByteData.sublistView(
      ConstantData(layouts, 0).moduleObjectData(module).bytes,
    );
    expect(bytes.lengthInBytes, holder.layout.size);
    expect(bytes.getUint64(holder.offsetOf(field), Endian.little), 0);
    final write = set.blocks
        .expand((b) => b.instructions)
        .whereType<StoreField>()
        .single;
    expect(write.field, same(field));
    expect(write.value, same(set.entry.parameters.single));
    final read = (get.entry.end as Return).value as LoadField;
    expect(read.field, same(field));
  });

  for (final late in [false, true]) {
    test(
      '${late ? "late" : "lazy"} nullable storage distinguishes null from unbound',
      () {
        final init = late ? null : FunctionTarget(uri, 'initialize', type, []);
        final global = GlobalVariable(
          uri,
          'flag',
          type,
          isLate: late,
          initializer: init,
        );
        final (:module, :layouts, :get, :set) = accessors(global);
        final holder = layouts.storageOf(module.type);
        final condition = get.entry.end as Branch;
        final bound = (condition.condition as LoadField).field;
        final value =
            ((condition.ifTrue.target.end as Return).value as LoadField).field;
        expect(holder.fields, unorderedEquals([value, bound]));
        expect(holder.layout.referenceOffsets, [
          ObjectHeader.typeOffset,
          holder.offsetOf(value),
        ]);
        final bytes = ByteData.sublistView(
          ConstantData(layouts, 0).moduleObjectData(module).bytes,
        );
        expect(bytes.getUint64(holder.offsetOf(bound), Endian.little), 0);
        final stores = set.entry.instructions.whereType<StoreField>().toList();
        expect(stores.map((s) => s.field), [value, bound]);
        expect(stores.first.value, same(set.entry.parameters.single));
        expect((stores.last.value as ScalarConstant).value, true);
        if (late) {
          expect(condition.ifFalse.target.end, isA<Throw>());
        } else {
          expect(
            condition.ifFalse.target.instructions.whereType<DirectCall>().map(
              (call) => call.target,
            ),
            [init, set.target],
          );
        }
      },
    );
  }
}
