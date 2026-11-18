import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:dartc/src/codegen/constant_data.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final carrier = ClassType(
    null,
    'RecordStorage',
    interfaces: [ValueType.record],
  );
  final user = ClassType(null, 'UserType', interfaces: [ValueType.typeType]);
  final classes = [
    IrClass(carrier, [], referencePayload: true, recordStorage: true),
    IrClass(user, []),
    for (final entry in TypeMetadata.fields.entries)
      IrClass(entry.key, entry.value),
  ];
  final inner = RecordConstant(RecordType([ValueType.typeType]), [
    TypeConstant(ValueType.integer),
  ]);
  final innerType = RecordType([TypeMetadata.type]);
  final proof = PromotedType(ValueType.object, ValueType.integer);
  final target = FunctionTarget(null, 'provedResult', proof, []);
  final parameter = TypeParameterType('T')..initializeBound(.object.nullable);
  final generic = FunctionTarget(
    null,
    'identity',
    parameter,
    [parameter],
    typeParameters: [parameter],
  );
  final genericBlock = Block(generic.parameterTypes);
  // The generic body uses its own block parameter; no invocation is mocked.
  genericBlock.finish(Return(genericBlock.parameters.single));
  final functions = [
    IrFunction(target, [Block()..finish(const Return(Constant.integer(42)))]),
    IrFunction(generic, [genericBlock]),
  ];
  final callable = FunctionConstant(target);
  final applied = FunctionConstant(generic, typeArguments: [proof]);
  final cases = <(String, RecordConstant, RecordType)>[
    ('original reviewer input', inner, innerType),
    (
      'nested positional and named',
      RecordConstant(RecordType([inner.type], {'label': ValueType.typeType}), [
        inner,
        TypeConstant(ValueType.string),
      ]),
      RecordType([innerType], {'label': TypeMetadata.type}),
    ),
    (
      'user Type implementation',
      RecordConstant(
        RecordType([], {
          'builtin': ValueType.typeType,
          'user': ValueType.typeType,
        }),
        [TypeConstant(ValueType.integer), ObjectConstant(user, {})],
      ),
      RecordType([], {'builtin': TypeMetadata.type, 'user': user}),
    ),
    (
      'reified function signature',
      RecordConstant(
        RecordType([ValueType.function], {'typed': ValueType.typeType}),
        [callable, TypeConstant(ValueType.integer)],
      ),
      RecordType(
        [FunctionType(ValueType.object, [])],
        {'typed': TypeMetadata.type},
      ),
    ),
    (
      'reified instantiated signature',
      RecordConstant(RecordType([ValueType.function]), [applied]),
      RecordType([
        FunctionType(ValueType.object, [ValueType.object]),
      ]),
    ),
  ];

  for (final (name, record, actual) in cases) {
    test(
      '$name agrees before and after simplification and in encoded metadata',
      () {
        final staticType = record.type, key = record.structuralKey;
        final block = Block();
        final check = block.emit(TypeTest(record, actual));
        block.finish(Return(check));
        final root = IrFunction(FunctionTarget(null, 'check', .boolean, []), [
          block,
        ]);
        final observedBlock = Block();
        final observed = observedBlock.emit(
          ObjectRuntimeType(record, direct: true),
        );
        observedBlock.finish(
          Return(observedBlock.emit(Equals(observed, TypeConstant(actual)))),
        );
        final observedRoot = IrFunction(
          FunctionTarget(null, 'observed', .boolean, []),
          [observedBlock],
        );
        final dynamicBlock = Block();
        final made = dynamicBlock.emit(
          MakeRecord(record.type as RecordType, record.fields),
        );
        final madeType = dynamicBlock.emit(
          ObjectRuntimeType(made, direct: true),
        );
        dynamicBlock.finish(
          Return(dynamicBlock.emit(Equals(madeType, TypeConstant(actual)))),
        );
        final dynamicRoot = IrFunction(
          FunctionTarget(null, 'made', .boolean, []),
          [dynamicBlock],
        );
        final bodies = [...functions, root, observedRoot, dynamicRoot];
        final closures = ClosureStorage(bodies);
        final layout = ProgramLayout(
          [...classes, ...closures.classes],
          nativeLayout: NativeLayout(const Target(.linux, .arm64)),
          closureStorage: closures,
        );
        final program = IrProgram(classes, bodies);
        final facts = ProgramFlow(
          program,
          [],
          openEntries: [root.target, observedRoot.target],
          memoryLayout: layout,
        ).facts;
        expect(record.runtimeValueType, actual);
        expect((facts.valueOf(check).constant as ScalarConstant).value, isTrue);
        final rewritten = const ProgramSimplification().run(facts);
        for (final current in [program, rewritten]) {
          final interpreter = IrInterpreter(current, {}, typeLayout: layout);
          for (final target in [root.target, observedRoot.target]) {
            expect(
              interpreter.run(
                current.implementationOf(target) as IrFunction,
                [],
              ),
              isTrue,
            );
          }
        }
        expect(
          IrInterpreter(program, {}, typeLayout: layout).run(dynamicRoot, []),
          isTrue,
        );
        final data = ConstantData(layout, 0);
        final symbol = data.addressOf(record);
        final actualSymbol = data.addressOf(TypeConstant(actual));
        final typeRelocation = data.relocations.singleWhere(
          (r) =>
              r.section == 1 &&
              r.offset == data.symbols[symbol].offset + ObjectHeader.typeOffset,
        );
        expect(typeRelocation.symbol, actualSymbol);
        expect(data.addressOf(record), symbol);
        expect(record.type, same(staticType));
        expect(record.structuralKey, key);
        for (final function in [callable, applied]) {
          if (closures.constants[function.structuralKey] case final storage?) {
            expect(storage.signature.reify(), function.runtimeValueType);
            final fnSymbol = data.addressOf(function);
            final fnType = data.addressOf(
              TypeConstant(function.runtimeValueType),
            );
            expect(
              data.relocations
                  .singleWhere(
                    (r) =>
                        r.section == 1 &&
                        r.offset ==
                            data.symbols[fnSymbol].offset +
                                ObjectHeader.typeOffset,
                  )
                  .symbol,
              fnType,
            );
          }
        }
      },
    );
  }

  test('record field composition does not promote a user Type to built-in metadata', () {
    final record = RecordConstant(RecordType([ValueType.typeType]), [
      ObjectConstant(user, {}),
    ]);
    final fact = FlowValue.constant(record)
        .check(RecordType([TypeMetadata.type]), runtimeTypes: true);
    expect(fact.value.isBottom, isTrue);
    expect(fact.mayFail, isTrue);
    expect(record.runtimeValueType, RecordType([user]));
  });
}
