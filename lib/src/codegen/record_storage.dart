import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/runtime/contracts.dart' show TypeKind;

import 'type_values.dart';

/// Selects record payload layout; ordinary SDK methods own record behavior.
final class RecordStorage(
  Iterable<IrClass> classes,
  Iterable<RecordType> records,
) {
  final declaration = classes.where((c) => c.recordStorage).singleOrNull;
  final shapes = {for (final record in records) _shape(record)};
  final _functions = <Object, IrFunction>{};

  ClassType get type =>
      declaration?.type ??
      (throw ArgumentError('Records require checked SDK storage.'));
  Iterable<IrFunction> get functions => _functions.values;

  IrClass? get generatedClass => _functions.isEmpty
      ? null
      : IrClass(
          type,
          const [],
          members: _functions.values
              .map((f) => f.target)
              .where((t) => t.kind.isVirtual),
          referencePayload: true,
          recordStorage: true,
        );

  static RecordType _shape(RecordType type) =>
      RecordType(List.filled(type.positionalCount, ValueType.object.nullable), {
        for (final name in type.slots.keys.skip(type.positionalCount))
          name: ValueType.object.nullable,
      });

  int shapeId(RecordType shape, TypeValues types) =>
      (types.constant(shape).fields[TypeMetadata.shape]! as ScalarConstant)
              .value
          as int;

  FunctionTarget create(RecordType record, TypeValues types) =>
      _functions.putIfAbsent(_shape(record), () {
        final shape = _shape(record);
        final target = FunctionTarget(
          null,
          'record${_functions.length}',
          type,
          shape.fields,
        );
        final block = Block(target.parameterTypes);
        final metadata = types.constant(shape);
        final actual = types.construct(
          block,
          TypeKind.record,
          shapeId(shape, types),
          [
            for (final field in block.parameters)
              block.emit(
                TypeCast(
                  block.emit(ObjectRuntimeType(field, direct: true)),
                  TypeMetadata.type,
                ),
              ),
          ],
          signature: metadata.fields[TypeMetadata.signature],
        );
        final value = block.emit(
          NewPayload(
            type,
            Constant.integer(shape.fields.length * ObjectHeader.alignment),
          ),
        );
        block.emit(
          StoreObjectReference(
            value,
            const Constant.integer(ObjectHeader.typeOffset),
            actual,
          ),
        );
        for (final (i, field) in block.parameters.indexed) {
          block.emit(
            StoreObjectReference(value, Constant.integer(offset(i)), field),
          );
        }
        block.finish(Return(value));
        return IrFunction(target, [block]);
      }).target;

  static int offset(int slot) =>
      ObjectHeader.fieldsOffset + slot * ObjectHeader.alignment;

  Iterable<RecordType> fieldsFor(MemberSelector selector) =>
      selector.privateScope != null || selector.kind == .setter
      ? const []
      : shapes.where((shape) => shape.slots.containsKey(selector.name));

  /// A dynamic field getter, entered only after the caller checks its shape.
  FunctionTarget? getter(MemberSelector selector, TypeValues types) {
    final matches = fieldsFor(selector).toList();
    if (matches.isEmpty) return null;
    return _functions.putIfAbsent(selector.name, () {
      final target = FunctionTarget(
        null,
        selector.name,
        .object.nullable,
        [],
        owner: type,
        kind: .getter,
      );
      final entry = Block(target.parameterTypes), blocks = [entry];
      var current = entry;
      final receiver = entry.parameters.single;
      final actual = entry.emit(
        TypeCast(
          entry.emit(ObjectRuntimeType(receiver, direct: true)),
          TypeMetadata.type,
        ),
      );
      final shape = entry.emit(LoadField(TypeMetadata.shape, actual));
      for (final (i, record) in matches.indexed) {
        var found = current;
        if (i != matches.length - 1) {
          found = Block();
          final next = Block();
          blocks.addAll([found, next]);
          current.finish(
            Branch(
              current.emit(
                Equals(shape, Constant.integer(shapeId(record, types))),
              ),
              Jump(found),
              Jump(next),
            ),
          );
          current = next;
        }
        found.finish(
          Return(
            found.emit(
              LoadObjectReference(
                receiver,
                Constant.integer(offset(record.slots[selector.name]!)),
              ),
            ),
          ),
        );
      }
      return IrFunction(target, blocks);
    }).target;
  }
}
