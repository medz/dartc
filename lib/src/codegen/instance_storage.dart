import 'package:dartc/ir.dart';

/// Physical field aliases and the SDK error path shared by late bindings.
final class InstanceStorage(
  Iterable<IrFunction> bodies, {
  IrCallable? lateError,
}) {
  final _slots = <InstanceField, (InstanceField, InstanceField)>{};
  IrFunction? failure;

  this {
    if (!bodies.any(
      (body) =>
          body.target.parameterTypes.any(
            (type) => type is CellType && type.isLate,
          ) ||
          body.fields.any(
            (field) =>
                field.isLate && (field.isFinal || field.initializer == null),
          ) ||
          body.blocks.any(
            (block) =>
                [
                  ...block.instructions,
                  if (block.end case Invoke(:final operation)) operation,
                ].any(
                  (value) =>
                      value is NewCell && (value.type as CellType).isLate,
                ),
          ),
    )) {
      return;
    }
    if (lateError == null) {
      throw UnsupportedError(
        'Native late storage requires the SDK dart:_internal LateError constructor.',
      );
    }
    final target = FunctionTarget(null, 'fail', .never, [.string]);
    final entry = Block(target.parameterTypes);
    entry.finish(
      Throw(entry.emit(Construct(lateError.target, entry.parameters))),
    );
    failure = IrFunction(target, [entry]);
  }

  Iterable<IrFunction> get functions => [?failure];

  (InstanceField, InstanceField) slots(InstanceField field) =>
      _slots.putIfAbsent(
        field,
        () => (
          InstanceField(field.owner, '${field.name}.value', field.type),
          InstanceField(field.owner, '${field.name}.bound', .boolean),
        ),
      );
}
