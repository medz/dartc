import 'dart:ffi' as ffi;

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test('operand mapping visits supplied positions before named arguments', () {
    final owner = ClassType(null, 'MappingReceiver');
    final member = FunctionTarget(
      null,
      'invoke',
      .integer,
      [.integer, .integer, .integer],
      owner: owner,
      kind: .method,
      namedParameters: {'last': true},
    );
    final target = FunctionTarget(
      null,
      'invoke',
      .integer,
      [.integer, .integer, .integer],
      namedParameters: {'last': true},
    );
    final receiver = Block([owner]).parameters.single;
    final shared = Block([ValueType.integer]).parameters.single;
    const tail = Constant.integer(3);
    final selector = (
      kind: FunctionKind.method,
      name: 'invoke',
      privateScope: null,
    );
    final calls = <Instruction>[
      InstanceCall(member, receiver, [shared, shared], {'last': tail}),
      FunctionCall(FunctionConstant(target), [shared, shared], {'last': tail}),
      DynamicDispatch(receiver, selector, [shared, shared], {'last': tail}),
      MakeInvocation(selector, [shared, shared], {'last': tail}),
    ];
    for (final call in calls) {
      final visited = <Value>[];
      var occurrence = 0;
      final copy = call.mapInputs((value) {
        visited.add(value);
        return identical(value, shared)
            ? Constant.integer(++occurrence)
            : value;
      });
      expect(
        visited,
        orderedEquals(call.inputs),
        reason: '${call.runtimeType}',
      );
      expect(occurrence, 2);
      final values = copy.inputs.whereType<Constant>().toList();
      expect(
        values.whereType<FunctionConstant>(),
        hasLength(call is FunctionCall ? 1 : 0),
      );
      expect(values.whereType<ScalarConstant>().map((v) => v.value), [1, 2, 3]);
    }
  });

  test('raw native mapping visits result storage before arguments', () {
    final result = NativeCompoundType('MappingResult', [
      NativeField('value', NativeScalarType(ffi.Int64)),
    ]);
    final operands = Block(List.filled(4, ValueType.integer)).parameters;
    final call = RawNativeCall(
      operands[0],
      NativeSignature.types(result, [
        NativeScalarType(ffi.Int64),
        NativeScalarType(ffi.Int64),
      ]),
      operands.skip(2),
      resultStorage: operands[1],
    );
    final visited = <Value>[];
    final copy = call.mapInputs((value) {
      visited.add(value);
      return Constant.integer(visited.length);
    }) as RawNativeCall;
    expect(visited, orderedEquals(operands));
    expect((copy.address as ScalarConstant).value, 1);
    expect((copy.resultStorage as ScalarConstant).value, 2);
    expect(copy.arguments.cast<ScalarConstant>().map((v) => v.value), [3, 4]);
  });

  test(
    'native remapping retains leaf calls, nominal signatures and owners',
    () {
      final native = NativeSignature(ffi.Int64, [
        ffi.Pointer<ffi.Void>,
        ffi.Int64,
      ]);
      final dart = FunctionType(.integer, [
        FfiTypes.pointerTypes[ffi.Pointer<ffi.Void>]!,
        .integer,
      ]);
      final pointer = NativeSymbolAddress(
        NativeReference(
          'test',
          'read',
          NativeFunctionType(native),
          isLeaf: true,
        ),
      );
      final before = Block([ValueType.object, ValueType.integer]);
      final after = Block([ValueType.object, ValueType.integer]);
      final call = NativeCall.symbol(
        pointer,
        dart,
        [before.parameters[1], const Constant.integer(2)],
        borrowedOwners: {0: before.parameters[0]},
      );
      final copy = call.mapInputs(
        (value) => switch (value) {
          final BlockParameter parameter =>
            after.parameters[before.parameters.indexOf(parameter)],
          final NativeSymbolAddress address => address.mapInputs((v) => v),
          _ => value,
        },
      ) as NativeCall;
      expect(copy.signature, native);
      expect(copy.dartSignature, same(dart));
      expect(copy.isLeaf, isTrue);
      expect(copy.arguments.first, same(after.parameters[1]));
      expect(copy.borrowedOwners, {0: after.parameters[0]});
      expect(
        (copy.pointer as NativeSymbolAddress).reference,
        same(pointer.reference),
      );
      expect(copy.pointer, isNot(same(pointer)));
      expect(call.borrowedOwners, {0: before.parameters[0]});
      final narrowed = NativeSymbolAddress(
        NativeReference(
          'test',
          'narrow',
          NativeFunctionType(
            NativeSignature(ffi.Int32, [ffi.Pointer<ffi.Void>, ffi.Int64]),
          ),
          isLeaf: true,
        ),
      );
      expect(narrowed.type, pointer.type);
      expect(
        () => call.mapInputs(
          (value) => identical(value, pointer) ? narrowed : value,
        ),
        throwsArgumentError,
      );
      expect(
        () => call.mapInputs(
          (value) => identical(value, before.parameters[0])
              ? const Constant.string('wrong type')
              : value,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'callbacks retain declared native types and get distinct instructions',
    () {
      final target = FunctionTarget(
        Uri.parse('memory:remap'),
        'callback',
        .integer,
        [.integer],
      );
      final native = FunctionType(FfiTypes.int64, [FfiTypes.int64]);
      final callback = NativeCallbackAddress(
        StaticCallbackTarget(
          target,
          native,
          exceptionalReturn: const Constant.integer(-1),
        ),
      );
      final copy =
          callback.mapInputs((value) => value) as NativeCallbackAddress;
      expect(copy, isNot(same(callback)));
      expect(copy.target, same(callback.target));
      expect((copy.target as StaticCallbackTarget).function, same(target));
      expect(copy.target.nativeType, same(native));
    },
  );

  test(
    'generic remapping substitutes storage and lexical call types together',
    () {
      final parameter = TypeParameterType('T')
        ..initializeBound(.object.nullable);
      final box = ClassType(null, 'Box', typeParameters: [parameter]);
      final field = InstanceField(box, 'value', parameter);
      final initializer = FunctionTarget(
        null,
        'new',
        .voidType,
        [parameter],
        owner: box,
        kind: .initializer,
      );
      final method = FunctionTarget(
        null,
        'read',
        parameter,
        [],
        owner: box,
        kind: .getter,
      );
      final before = Block([box, parameter]);
      final actual = box.instantiate([ValueType.integer]);
      final after = Block([actual, ValueType.integer]);
      Value replace(Value value) => value is BlockParameter
          ? after.parameters[before.parameters.indexOf(value)]
          : value;
      const one = Constant.integer(1);
      final environment = {parameter: ValueType.integer};
      final load = LoadField(
        field,
        before.parameters[0],
      ).mapInputs(replace, environment: environment) as LoadField;
      expect(load.type, ValueType.integer);
      expect(load.field, same(field));
      final construct = Construct(initializer, [
        before.parameters[1],
      ]).mapInputs(replace, environment: environment) as Construct;
      expect(construct.instantiatedType, actual);
      final call = DirectCall(
        method,
        [before.parameters[0]],
        ownerType: box,
      ).mapInputs(replace, environment: environment) as DirectCall;
      expect(call.type, ValueType.integer);
      expect(call.target, same(method));
      expect(call.ownerType, actual);
      final reified = ReifyType(
        CoreTypes.listOf(parameter),
      ).mapInputs(replace, environment: environment) as ReifyType;
      expect(reified.template, CoreTypes.listOf(.integer));
      final write = StoreField(
        field,
        before.parameters[0],
        before.parameters[1],
      );
      expect(() => write.mapInputs(replace), throwsArgumentError);
      final mapped =
          write.mapInputs(replace, environment: environment) as StoreField;
      expect(mapped.receiver, same(after.parameters[0]));
      expect(mapped.value, same(after.parameters[1]));
      expect(
        () => LoadField(
          field,
          before.parameters[0],
        ).mapInputs((_) => one, environment: environment),
        throwsArgumentError,
      );
    },
  );

  test('named order, type arguments and storage flags survive remapping', () {
    final before = Block([ValueType.object, ValueType.integer]);
    final after = Block([ValueType.object, ValueType.integer]);
    final selector = (
      kind: FunctionKind.method,
      name: 'invoke',
      privateScope: null,
    );
    final type = TypeParameterType('T')..initializeBound(.object.nullable);
    final fallback = FunctionTarget(
      null,
      'missing',
      .dynamicType,
      List.filled(4, ValueType.dynamicType),
      typeParameters: [type],
    );
    final getter = FunctionTarget(
      null,
      'invoke',
      .dynamicType,
      [],
      owner: ClassType(null, 'Getter'),
      kind: .getter,
    );
    final call = DynamicDispatch(
      before.parameters[0],
      selector,
      [before.parameters[1]],
      {'second': before.parameters[1], 'first': const Constant.integer(1)},
      [ValueType.string],
      fallback,
      {getter: fallback},
    );
    Value remap(Value value) => value is BlockParameter
        ? after.parameters[before.parameters.indexOf(value)]
        : value;
    final copy = call.mapInputs(remap) as DynamicDispatch;
    expect(copy.selector, selector);
    expect(copy.failure, same(fallback));
    expect(copy.getterCalls, {getter: fallback});
    expect(copy.named.keys, ['second', 'first']);
    expect(copy.named['second'], same(after.parameters[1]));
    expect(copy.typeArguments, [ValueType.string]);
    final late = CellType(ValueType.integer, isLate: true, isFinal: true);
    final cell = NewCell(late, before.parameters[1]);
    final copiedCell = cell.mapInputs(remap) as NewCell;
    expect(copiedCell.type, late);
    expect(copiedCell.initial, same(after.parameters[1]));
  });
}
