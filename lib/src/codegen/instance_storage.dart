import 'package:dartc/ir.dart';

/// Physical aliases and the ordinary SDK error path for instance late bindings.
final class InstanceStorage(
  Iterable<IrFunction> bodies, {
  IrCallable? lateError,
}) {
  final _slots = <InstanceField, (InstanceField, InstanceField)>{};
  IrFunction? failure;

  this {
    if (!bodies.any(
      (body) => body.fields.any(
        (field) => field.isLate && (field.isFinal || field.initializer == null),
      ),
    )) {
      return;
    }
    if (lateError == null) {
      throw UnsupportedError(
        'Native late instance storage requires the SDK dart:_internal LateError constructor.',
      );
    }
    final target = FunctionTarget(
      Uri.parse('dartc:instance-storage'),
      'fail',
      .never,
      [.string],
    );
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
