import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/runtime/contracts.dart' show TypeKind;
import 'package:dartc/src/codegen/constant_data.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  const target = Target(.linux, .arm64);
  final t = TypeParameterType('T')..initializeBound(.object.nullable);
  final box = ClassType(null, 'Box', typeParameters: [t]);
  final classes = [
    IrClass(box, []),
    for (final entry in TypeMetadata.fields.entries)
      IrClass(entry.key, entry.value),
  ];
  ProgramLayout layout({TypeImplementations? owner}) => ProgramLayout(
    classes,
    nativeLayout: NativeLayout(target),
    typeImplementations: owner,
  );

  test('built-in type constants retain static identity and establish only their real runtime type', () {
    final literal = TypeConstant(ValueType.integer);
    final key = literal.structuralKey;
    expect(literal.type, ValueType.typeType);
    expect(literal.runtimeValueType, TypeMetadata.type);
    final fact = FlowValue.constant(literal);
    expect(fact.types, [TypeMetadata.type]);
    expect(fact.mayHaveInstance(TypeMetadata.type), isTrue);
    for (final runtimeTypes in [false, true]) {
      final checked = fact.check(TypeMetadata.type, runtimeTypes: runtimeTypes);
      expect(checked.value.constant, same(literal));
      expect(checked.mayFail, isFalse);
      expect(checked.value.constant!.structuralKey, key);
    }
    final user = ClassType(null, 'UserType', interfaces: [ValueType.typeType]);
    final object = ObjectConstant(user, {});
    expect(object.runtimeValueType, user);
    expect(
      FlowValue.constant(object).mayHaveInstance(TypeMetadata.type),
      isFalse,
    );
    expect(
      FlowValue.constant(object).check(TypeMetadata.type).value.isBottom,
      isTrue,
    );
  });

  test(
    'shared layout owner keeps descriptor identities across graph layouts',
    () {
      final owner = TypeImplementations();
      final first = layout(owner: owner), second = layout(owner: owner);
      expect(first.types, same(second.types));
      expect(first.relations, same(second.relations));
      final value = TypeConstant(box.instantiate([ValueType.integer]));
      final before = first.typeRevision;
      final view = first.typeConstant(value);
      expect(first.typeRevision, greaterThan(before));
      final stable = first.typeRevision;
      expect(second.typeConstant(value).structuralKey, view.structuralKey);
      expect(second.typeRevision, stable);
      expect(
        second.canonicalTypeConstant(view)!.structuralKey,
        value.structuralKey,
      );
      expect(layout().types, isNot(same(first.types)));
    },
  );

  test('nested type fields preserve canonical identity in analysis and interpretation', () {
    final storage = layout();
    final argument = TypeConstant(ValueType.integer);
    final outer = TypeConstant(box.instantiate([ValueType.integer]));
    final entry = Block();
    final view = entry.emit(UncheckedCast(outer, TypeMetadata.type));
    final parts = entry.emit(
      NullCheck(entry.emit(LoadField(TypeMetadata.parts, view))),
    );
    final head = entry.emit(LoadField(TypeMetadata.head, parts));
    final identity = entry.emit(Identical(head, argument));
    final equals = entry.emit(Equals(head, argument));
    final hash = entry.emit(ObjectHashCode(head));
    final expectedHash = entry.emit(ObjectHashCode(argument));
    final hashEqual = entry.emit(Equals(hash, expectedHash));
    entry.finish(Return(identity));
    final root = IrFunction(FunctionTarget(null, 'identity', .boolean, []), [
      entry,
    ]);
    final program = IrProgram(classes, [root]);
    final facts = ProgramFlow(
      program,
      [],
      openEntries: [root.target],
      memoryLayout: storage,
    ).facts;
    expect(facts.valueOf(view).constant, same(outer));
    expect(facts.valueOf(head).constant, isA<TypeConstant>());
    expect(facts.valueOf(head).constant!.structuralKey, argument.structuralKey);
    expect(
      facts.valueOf(identity).constant!.structuralKey,
      const Constant.boolean(true).structuralKey,
    );
    expect(
      facts.valueOf(equals).constant!.structuralKey,
      const Constant.boolean(true).structuralKey,
    );
    final interpreter = IrInterpreter(program, {}, typeLayout: storage);
    expect(interpreter.run(root, []), isTrue);
    // Expose each observable independently through the same already-built body.
    for (final result in [equals, hashEqual]) {
      final body = FunctionRewrite(
        root,
        terminators: {entry: Return(result)},
      ).run();
      expect(
        IrInterpreter(
          IrProgram(classes, [body]),
          {},
          typeLayout: storage,
        ).run(body, []),
        isTrue,
      );
    }
    expect(() => IrInterpreter(program, {}).run(root, []), throwsStateError);
    expect(
      () => ProgramFlow(program, [], openEntries: [root.target]),
      throwsStateError,
    );
  });

  test('nested type descriptors and source type constants share one emitted address', () {
    final storage = layout();
    final argument = TypeConstant(ValueType.integer);
    final outer = TypeConstant(box.instantiate([ValueType.integer]));
    final view = storage.typeConstant(outer);
    final parts = view.fields[TypeMetadata.parts] as ObjectConstant;
    final nested = parts.fields[TypeMetadata.head] as ObjectConstant;
    final constants = ConstantData(storage, 0);
    final outerAddress = constants.addressOf(outer);
    expect(constants.addressOf(view), outerAddress);
    final argumentAddress = constants.addressOf(argument);
    expect(constants.addressOf(nested), argumentAddress);
    final partsAddress = constants.addressOf(parts);
    final headOffset =
        constants.symbols[partsAddress].offset +
        storage.fieldOffset(TypeMetadata.head);
    expect(
      constants.relocations
          .singleWhere((r) => r.section == 1 && r.offset == headOffset)
          .symbol,
      argumentAddress,
    );
  });

  test('generic function binders remain metadata rather than fabricated closed type constants', () {
    final storage = layout();
    final p = TypeParameterType('P')..initializeBound(.object.nullable);
    final value = TypeConstant(FunctionType(p, [p], typeParameters: [p]));
    final view = storage.typeConstant(value);
    final pending = <ObjectConstant>[view];
    var parameters = 0;
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (current.type == TypeMetadata.type &&
          current.fields[TypeMetadata.kind]!.structuralKey ==
              Constant.integer(TypeKind.parameter.index).structuralKey) {
        parameters++;
        expect(storage.canonicalTypeConstant(current), isNull);
      }
      pending.addAll(current.fields.values.whereType<ObjectConstant>());
    }
    expect(parameters, 2);
    expect(
      storage.canonicalTypeConstant(view)!.structuralKey,
      value.structuralKey,
    );
  });
}
