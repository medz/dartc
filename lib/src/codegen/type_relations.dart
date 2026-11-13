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

  Iterable<IrFunction> get functions => [?_parents, ..._views.values];

  /// Projects a closed instance type onto its declaring superclass or interface.
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
              : values.build(found, view, {
                  for (final (i, parameter)
                      in declaration.typeParameters.indexed)
                    parameter: _part(found, actual, _int(i)),
                }),
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

  IrFunction? _parents;
  IrFunction get supertypes => _parents ??= _parentProjection();

  IrFunction _parentProjection() {
    final target = values.runtime!.supertypes;
    final entry = Block(target.parameterTypes), nominal = Block();
    final missing = Block()..finish(const Return(Constant.nullValue()));
    final blocks = [entry, nominal, missing];
    final actual = entry.parameters.single;
    final kind = _load(entry, TypeMetadata.kind, actual);
    if (recordStorage case final storage?) {
      final record = Block();
      blocks.add(record);
      _equal(entry, kind, _int(TypeKind.record.index), record, nominal);
      record.finish(Return(values.argumentConstants([storage])));
    } else {
      entry.finish(Jump(nominal));
    }
    final shape = _load(nominal, TypeMetadata.shape, actual);
    var current = nominal;
    for (final declaration in _declarations) {
      final parents = [?declaration.superclass, ...declaration.interfaces];
      if (parents.isEmpty) continue;
      final selected = Block(), next = Block();
      blocks.addAll([selected, next]);
      _equal(current, shape, _int(values.id(declaration)), selected, next);
      final environment = {
        for (final (i, parameter) in declaration.typeParameters.indexed)
          parameter: _part(selected, actual, _int(i)),
      };
      Value result = const Constant.nullValue();
      for (final parent in parents.reversed) {
        final value = values.build(
          selected,
          parent,
          environment,
          shift: (value, count) => selected.emit(
            DirectCall(values.entry(.typeShift), [value, _int(count), _int(0)]),
          ),
        );
        result = selected.emit(values.cons(value, result));
      }
      selected.finish(Return(result));
      current = next;
    }
    current.finish(Jump(missing));
    return IrFunction(target, blocks);
  }
}
