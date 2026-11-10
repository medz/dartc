import 'dart:typed_data';

import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  final library = Uri.parse('memory:constants');
  const one = Constant.integer(1);
  const two = Constant.integer(2);
  const text = Constant.string('value');

  test('collection spreads distinguish literals from checked addAll calls', () {
    final list = NewCollection(CoreTypes.listOf(ValueType.integer));
    final source = SequenceConstant(CoreTypes.listOf(ValueType.integer), []);
    expect(CollectionSpread(list, source).isMethodCall, isFalse);
    final call = CollectionSpread(list, source, isMethodCall: true);
    expect(call.isMethodCall, isTrue);
    expect(call.inputs, [list, source]);
    final map = NewCollection(
      CoreTypes.mapOf(ValueType.integer, ValueType.string),
    );
    final mapSource = MapConstant(
      CoreTypes.mapOf(ValueType.integer, ValueType.string),
      [],
    );
    expect(
      CollectionSpread(map, mapSource, isMethodCall: true).isMethodCall,
      isTrue,
    );
  });

  test('sequence constants retain type and order with immutable storage', () {
    final input = <Constant>[one, two];
    final list = SequenceConstant(CoreTypes.listOf(ValueType.integer), input);
    input.clear();
    expect(list.elements, [one, two]);
    expect(() => list.elements.add(one), throwsUnsupportedError);
    expect(
      list.structuralKey,
      SequenceConstant(CoreTypes.listOf(ValueType.integer), [
        one,
        two,
      ]).structuralKey,
    );
    expect(
      list.structuralKey,
      isNot(
        SequenceConstant(CoreTypes.listOf(ValueType.integer), [
          two,
          one,
        ]).structuralKey,
      ),
    );
    expect(
      list.structuralKey,
      isNot(
        SequenceConstant(CoreTypes.setOf(ValueType.integer), [
          one,
          two,
        ]).structuralKey,
      ),
    );
    expect(() => SequenceConstant(ValueType.object, []), throwsArgumentError);
    expect(
      () => SequenceConstant(CoreTypes.listOf(ValueType.integer), [text]),
      throwsArgumentError,
    );
  });

  test(
    'map constants retain entries and reject incompatible keys and values',
    () {
      final type = CoreTypes.mapOf(ValueType.integer, ValueType.string);
      final input = <(Constant, Constant)>[(one, text), (two, text)];
      final map = MapConstant(type, input);
      input.clear();
      expect(map.entries, [(one, text), (two, text)]);
      expect(() => map.entries.clear(), throwsUnsupportedError);
      expect(map.structuralKey, MapConstant(type, map.entries).structuralKey);
      expect(
        map.structuralKey,
        isNot(MapConstant(type, map.entries.reversed).structuralKey),
      );
      expect(() => MapConstant(type, [(text, text)]), throwsArgumentError);
      expect(() => MapConstant(type, [(one, two)]), throwsArgumentError);
      expect(() => MapConstant(ValueType.object, []), throwsArgumentError);
    },
  );

  test(
    'object identity uses actual type and declared slots, not map order',
    () {
      final parent = ClassType(library, 'Parent');
      final child = ClassType(library, 'Child', superclass: parent);
      final inherited = InstanceField(
        parent,
        '_value',
        ValueType.integer,
        isFinal: true,
      );
      final own = InstanceField(
        child,
        '_value',
        ValueType.integer,
        isFinal: true,
      );
      final input = <InstanceField, Constant>{inherited: one, own: two};
      final object = ObjectConstant(child, input);
      input.clear();
      expect(object.fields.length, 2);
      expect(() => object.fields.clear(), throwsUnsupportedError);
      expect(
        object.structuralKey,
        ObjectConstant(child, {own: two, inherited: one}).structuralKey,
      );
      expect(
        object.structuralKey,
        isNot(ObjectConstant(child, {inherited: two, own: one}).structuralKey),
      );
      expect(
        ObjectConstant(parent, {inherited: one}).structuralKey,
        isNot(ObjectConstant(child, {inherited: one}).structuralKey),
      );
      final other = ClassType(Uri.parse('memory:other'), 'Parent');
      final foreign = InstanceField(
        other,
        '_value',
        ValueType.integer,
        isFinal: true,
      );
      expect(() => ObjectConstant(child, {foreign: one}), throwsArgumentError);
      expect(
        () => ObjectConstant(child, {inherited: text}),
        throwsArgumentError,
      );
      expect(
        () => ObjectConstant(child, {
          InstanceField(child, 'mutable', ValueType.integer): one,
        }),
        throwsArgumentError,
      );
      expect(
        () => ObjectConstant(
          ClassType(library, 'Abstract', isAbstract: true),
          {},
        ),
        throwsArgumentError,
      );
    },
  );

  test('object field checks substitute inherited generic types', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final parent = ClassType(library, 'Box', typeParameters: [t]);
    final child = ClassType(
      library,
      'IntBox',
      superclass: parent.instantiate([ValueType.integer]),
    );
    final field = InstanceField(parent, 'value', t, isFinal: true);
    expect(ObjectConstant(child, {field: one}).fields[field], same(one));
    expect(() => ObjectConstant(child, {field: text}), throwsArgumentError);
  });

  test('scalar keys preserve numeric representation and signed zero', () {
    expect(
      one.structuralKey,
      isNot(const Constant.floating(1.0).structuralKey),
    );
    expect(
      const Constant.floating(-0.0).structuralKey,
      isNot(const Constant.floating(0.0).structuralKey),
    );
    expect(
      const Constant.floating(double.nan).structuralKey,
      const Constant.floating(double.nan).structuralKey,
    );
    final keys = <Object>{};
    for (final bits in [
      0x7ff8000000000001,
      0x7ff8000000000002,
      0xfff8000000000001,
    ]) {
      final value = (ByteData(8)..setUint64(0, bits)).getFloat64(0);
      expect(value.isNaN, isTrue);
      keys.add(Constant.floating(value).structuralKey);
    }
    expect(keys, hasLength(3));
  });

  test('constructor keys normalize applied owner and proper aliases', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final box = ClassType(library, 'Box', typeParameters: [t]);
    final ctor = FunctionTarget(
      library,
      'new',
      .voidType,
      [],
      owner: box,
      kind: .initializer,
    );
    final ints = box.instantiate([ValueType.integer]);
    expect(
      FunctionConstant(ctor, ownerType: ints).structuralKey,
      FunctionConstant(ctor, typeArguments: [ValueType.integer]).structuralKey,
    );
    final aliasT = TypeParameterType('T')
      ..initializeBound(ValueType.dynamicType);
    final view = FunctionType(
      box.instantiate([aliasT]),
      [],
      typeParameters: [aliasT],
    );
    expect(
      FunctionConstant(ctor).structuralKey,
      FunctionConstant(ctor, constructorSignature: view).structuralKey,
    );
    expect(
      FunctionConstant(ctor, ownerType: ints).structuralKey,
      FunctionConstant(
        ctor,
        constructorSignature: view,
        typeArguments: [ValueType.integer],
      ).structuralKey,
    );
    final plain = ClassType(library, 'Plain');
    final plainCtor = FunctionTarget(
      library,
      'new',
      .voidType,
      [],
      owner: plain,
      kind: .initializer,
    );
    expect(
      FunctionConstant(plainCtor).structuralKey,
      FunctionConstant(plainCtor, ownerType: plain).structuralKey,
    );
  });

  test('function keys retain phantom arguments and nominal alias identity', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final fn = FunctionTarget(
      library,
      'phantom',
      .integer,
      [],
      typeParameters: [t],
    );
    expect(
      FunctionConstant(fn, typeArguments: [ValueType.integer]).structuralKey,
      isNot(
        FunctionConstant(fn, typeArguments: [ValueType.string]).structuralKey,
      ),
    );
    final box = ClassType(library, 'Box');
    final ctor = FunctionTarget(
      library,
      'new',
      .voidType,
      [],
      owner: box,
      kind: .initializer,
    );
    final signature = FunctionType(box, [], typeParameters: [t]);
    FunctionConstant alias(String name, ValueType argument) => FunctionConstant(
      ctor,
      constructorSignature: signature,
      constructorAlias: (library, name),
      typeArguments: [argument],
    );
    expect(
      alias('Alias', ValueType.integer).structuralKey,
      isNot(alias('Alias', ValueType.string).structuralKey),
    );
    expect(
      alias('Alias', ValueType.integer).structuralKey,
      isNot(alias('Other', ValueType.integer).structuralKey),
    );
  });

  test(
    'nested constants are formatted and checked for hidden type parameters',
    () {
      final foreign = TypeParameterType('Foreign')
        ..initializeBound(ValueType.object.nullable);
      final hidden = SequenceConstant(CoreTypes.listOf(foreign), []);
      final holder = ClassType(library, 'Holder');
      final field = InstanceField(
        holder,
        'value',
        ValueType.object,
        isFinal: true,
      );
      final nested = ObjectConstant(holder, {
        field: MapConstant(
          CoreTypes.mapOf(ValueType.object, ValueType.object),
          [
            (
              one,
              SequenceConstant(CoreTypes.listOf(ValueType.object), [hidden]),
            ),
          ],
        ),
      });
      final target = FunctionTarget(library, 'nested', holder, []);
      expect(
        () => IrFunction(target, [Block([])..finish(Return(nested))]),
        throwsStateError,
      );
      final valid = ObjectConstant(holder, {
        field: SequenceConstant(CoreTypes.listOf(ValueType.integer), [one]),
      });
      final graph = IrFunction(target, [Block([])..finish(Return(valid))]);
      final output = StringBuffer();
      graph.writeTo(output);
      expect(
        output.toString(),
        contains(
          'const Holder{memory:constants::Holder.value: const List<int>[1]}',
        ),
      );
    },
  );
}
