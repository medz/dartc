import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  final type = ClassType(null, 'ModuleFields');
  final field = InstanceField(type, 'value', .integer);
  final optional = InstanceField(type, 'optional', .object.nullable);
  final declaration = IrClass(type, [field, optional]);

  test('module identity owns immutable explicit bindings without filling omissions', () {
    final fields = {field: const Constant.integer(7)};
    final module = ModuleObject(type, initialFields: fields);
    fields.clear();
    expect(module.initialFields[field], isA<Constant>());
    expect(module.initialFields.containsKey(optional), isFalse);
    expect(() => module.initialFields.clear(), throwsUnsupportedError);
    expect(
      ModuleObject(type, initialFields: module.initialFields),
      isNot(same(module)),
    );
    expect(
      () => ModuleObject(
        type,
        initialFields: {field: const Constant.nullValue()},
      ),
      throwsArgumentError,
    );
    final foreign = InstanceField(
      ClassType(null, 'Foreign'),
      'value',
      .integer,
    );
    expect(
      () => ModuleObject(
        type,
        initialFields: {foreign: const Constant.integer(1)},
      ),
      throwsArgumentError,
    );
  });

  test('module references retain identity, initial dependencies and fixed storage checks', () {
    final module = ModuleObject(
      type,
      initialFields: {field: const Constant.integer(7)},
    );
    final reference = ModuleObjectReference(module);
    final cloned = reference.mapInputs(
      (_) => throw StateError('No inputs'),
    ) as ModuleObjectReference;
    expect(cloned.declaration, same(module));
    expect(cloned.type, type);
    expect(cloned.effects, isEmpty);
    final block = Block();
    block.emit(reference);
    block.finish(Return(block.emit(cloned)));
    final function = IrFunction(FunctionTarget(null, 'module', type, []), [
      block,
    ]);
    expect(function.moduleObjects, {module});
    expect(function.fields, contains(field));
    IrProgram([declaration], [function]);
    final text = StringBuffer();
    function.writeTo(text);
    expect(text.toString(), contains('moduleObject0'));
    expect(text.toString(), isNot(contains('moduleObject1')));
    expect(() => IrProgram([], [function]), throwsArgumentError);

    final payload = ClassType(null, 'Variable');
    final body = Block();
    body.finish(
      Return(body.emit(ModuleObjectReference(ModuleObject(payload)))),
    );
    final invalid = IrFunction(
      FunctionTarget(null, 'payloadModule', payload, []),
      [body],
    );
    expect(
      () =>
          IrProgram([IrClass(payload, [], referencePayload: true)], [invalid]),
      throwsArgumentError,
    );
  });
}
