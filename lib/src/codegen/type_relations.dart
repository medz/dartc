import 'package:dartc/ir.dart';
import 'package:dartc/runtime/contracts.dart';

import 'type_values.dart';

/// Generates class projections from the compilation's nominal declarations.
final class TypeRelations(
  final TypeValues values,
  Iterable<ClassType> declarations, {
  final ClassType? recordStorage,
}) {
  final _declarations = <ClassType>{};
  final _views = <ClassType, IrFunction>{};

  this {
    void add(ClassType value) {
      if (!_declarations.add(value.declaration)) return;
      values.id(value.declaration);
      if (value.declaration.superclass case final parent?) add(parent);
      value.declaration.interfaces.forEach(add);
    }

    [
      ...declarations,
      ...values.classes.map((c) => c.type),
      ValueType.future,
      ValueType.function,
      ValueType.record,
      ValueType.integer,
      ValueType.floating,
      ValueType.boolean,
      FfiTypes.pointer,
    ].forEach(add);
  }

  FunctionTarget get test => values.entry(.typeSubtype);

  Iterable<IrFunction> get functions => [?_projection, ..._views.values];

  /// Projects an instance type onto its declaring superclass or interface.
  FunctionTarget viewOf(ClassType owner) => _views.putIfAbsent(owner, () {
    final target = FunctionTarget(
      null,
      'view${_views.length}',
      TypeMetadata.type.nullable,
      [TypeMetadata.type],
    );
    final entry = Block(target.parameterTypes), nominal = Block();
    final missing = Block()..finish(Return(const Constant.nullValue()));
    final blocks = [entry, nominal, missing];
    final actual = entry.parameters.single;
    _equal(
      entry,
      _load(entry, TypeMetadata.kind, actual),
      _int(TypeKind.nominal.index),
      nominal,
      missing,
    );
    final shape = _load(nominal, TypeMetadata.shape, actual);
    var current = nominal;
    for (final declaration in _declarations) {
      final view = declaration.asInstanceOf(owner);
      if (view == null) continue;
      final found = Block(), next = Block();
      blocks.addAll([found, next]);
      _equal(current, shape, _int(values.id(declaration)), found, next);
      found.finish(
        Return(
          declaration == owner
              ? actual
              : values.build(
                  found,
                  view,
                  {
                    for (final (i, parameter)
                        in declaration.typeParameters.indexed)
                      parameter: _part(found, actual, _int(i)),
                  },
                  shift: (value, count) => found.emit(
                    DirectCall(values.entry(.typeShift), [
                      value,
                      _int(count),
                      _int(0),
                    ]),
                  ),
                ),
        ),
      );
      current = next;
    }
    current.finish(Jump(missing));
    return IrFunction(target, blocks);
  }).target;

  static Constant _int(int value) => Constant.integer(value);
  static Value _load(Block block, InstanceField field, Value value) =>
      block.emit(LoadField(field, value));
  static void _equal(Block block, Value a, Value b, Block yes, Block no) =>
      block.finish(Branch(block.emit(Equals(a, b)), Jump(yes), Jump(no)));
  Value _part(Block block, Value value, Value index) => block.emit(
    DirectCall(values.entry(.typeAt), [
      _load(block, TypeMetadata.parts, value),
      index,
    ]),
  );

  IrFunction? _projection;
  IrFunction get projection => _projection ??= _typeProjection();

  IrFunction _typeProjection() {
    final target = values.runtime!.projection;
    final entry = Block(target.parameterTypes);
    final nominal = Block([TypeMetadata.type]);
    final missing = Block()..finish(const Return(Constant.nullValue()));
    final blocks = [entry, nominal, missing];
    final [actual, shape] = entry.parameters;
    if (recordStorage case final storage?) {
      final record = Block(), ordinary = Block();
      blocks.addAll([record, ordinary]);
      _equal(
        entry,
        _load(entry, TypeMetadata.kind, actual),
        _int(TypeKind.record.index),
        record,
        ordinary,
      );
      record.finish(Jump(nominal, [values.constant(storage)]));
      ordinary.finish(Jump(nominal, [actual]));
    } else {
      entry.finish(Jump(nominal, [actual]));
    }
    var current = nominal;
    for (final owner in _declarations) {
      final found = Block(), next = Block();
      blocks.addAll([found, next]);
      _equal(current, shape, _int(values.id(owner)), found, next);
      found.finish(
        Return(found.emit(DirectCall(viewOf(owner), nominal.parameters))),
      );
      current = next;
    }
    current.finish(Jump(missing));
    return IrFunction(target, blocks);
  }
}
