import 'package:dartc/ir.dart';

import 'type_values.dart';

/// Managed carrier layouts, separate from the closures' actual runtime types.
final class ClosureStorage(Iterable<IrFunction> selectedBodies) {
  static final _uri = Uri.parse('dartc:closures');
  final _base = ClassType(_uri, 'Closure');
  late final tag = InstanceField(_base, 'target', .integer);
  final closures = <FunctionTarget, ClosureShape>{};
  final _cells = <CellType, CellShape>{};
  final _classes = <IrClass>[];
  final _functions = <IrFunction>[];

  Iterable<IrClass> get classes => _classes;
  Iterable<IrFunction> get functions => _functions;

  this {
    final bodies = selectedBodies.toList();
    final targets = <FunctionTarget>{};
    void includeCell(ValueType type) {
      if (type is! CellType || _cells.containsKey(type)) return;
      final owner = ClassType(_uri, 'Cell${_cells.length}');
      final value = InstanceField(owner, 'value', _stored(type.content));
      final initializer = _initialize(owner, [value]);
      _cells[type] = CellShape(owner, value, initializer);
      _classes.add(IrClass(owner, [value], constructors: [initializer]));
    }

    for (final body in bodies) {
      if (body.target.kind == .closure) targets.add(body.target);
      for (final type in body.target.parameterTypes) {
        includeCell(type);
      }
      for (final block in body.blocks) {
        for (final parameter in block.parameters) {
          includeCell(parameter.type);
        }
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          includeCell(operation.type);
          for (final input in operation.inputs) {
            includeCell(input.type);
          }
          if (operation case MakeClosure(:final target)) targets.add(target);
        }
      }
    }
    if (targets.isNotEmpty) _classes.add(IrClass(_base, [tag]));
    for (final target in targets) {
      final index = closures.length;
      final owner = ClassType(_uri, 'Closure$index', superclass: _base);
      final captures = [
        for (final (i, type) in target.captures.indexed)
          InstanceField(owner, 'capture$i', _stored(type), isFinal: true),
      ];
      final enclosing = <FunctionTarget>[];
      for (
        var scope = target.enclosing;
        scope != null;
        scope = scope.enclosing
      ) {
        enclosing.add(scope);
      }
      final parameters = <TypeParameterType>{};
      for (final scope in enclosing.reversed) {
        if (scope.kind.hasReceiver || scope.kind == .factory) {
          parameters.addAll(scope.owner!.typeParameters);
        }
        parameters.addAll(scope.typeParameters);
      }
      final environment = [
        for (var i = 0; i < parameters.length; i++)
          InstanceField(owner, 'type$i', TypeValues.type, isFinal: true),
      ];
      final fields = [...captures, ...environment];
      final initializer = _initialize(owner, [tag, ...fields]);
      closures[target] = ClosureShape(
        index,
        owner,
        initializer,
        captures,
        parameters.toList(),
        environment,
      );
      _classes.add(IrClass(owner, fields, constructors: [initializer]));
    }
  }

  CellShape cell(CellType type) =>
      _cells[type] ?? (throw StateError('Uncollected native cell: $type'));

  Map<ClassType, FunctionTarget> targetsFor(FunctionCall call) => {
    for (final entry in closures.entries)
      if (_callableAt(call, entry.key)) entry.value.type: entry.key,
  };

  bool _callableAt(FunctionCall call, FunctionTarget target) {
    final view = call.function.type as FunctionType, actual = target.signature;
    if (actual.typeParameters.length != view.typeParameters.length) {
      return false;
    }
    if (actual.freeTypeParameters.isEmpty && view.freeTypeParameters.isEmpty) {
      return view.accepts(actual);
    }
    // Free lexical types are unknown here; fixed slots can still rule a target out.
    bool possible(ValueType expected, ValueType value) =>
        expected.freeTypeParameters.isNotEmpty ||
        value.freeTypeParameters.isNotEmpty ||
        expected.accepts(value);
    if (!possible(view.result, actual.result) ||
        actual.requiredPositional > view.requiredPositional ||
        actual.positionalCount < view.positionalCount) {
      return false;
    }
    for (var i = 0; i < view.positionalCount; i++) {
      if (!possible(actual.parameters[i], view.parameters[i])) return false;
    }
    for (final entry in view.named.entries) {
      final parameter = actual.named[entry.key];
      if (parameter == null ||
          !possible(
            actual.parameters[parameter.slot],
            view.parameters[entry.value.slot],
          )) {
        return false;
      }
    }
    return actual.named.entries.every(
      (entry) =>
          !entry.value.required || view.named[entry.key]?.required == true,
    );
  }

  ValueType _stored(ValueType type) =>
      type == .integer ||
          type == .boolean ||
          type == .floating ||
          FfiTypes.isPointer(type)
      ? type
      : ValueType.object.nullable;

  FunctionTarget _initialize(ClassType owner, List<InstanceField> fields) {
    final target = FunctionTarget(
      _uri,
      'new',
      .voidType,
      fields.map((field) => field.type),
      owner: owner,
      kind: .initializer,
    );
    final entry = Block(target.parameterTypes);
    for (final (i, field) in fields.indexed) {
      entry.emit(
        StoreField(field, entry.parameters.first, entry.parameters[i + 1]),
      );
    }
    entry.finish(const Return());
    _functions.add(IrFunction(target, [entry]));
    return target;
  }
}

final class ClosureShape(
  final int tag,
  final ClassType type,
  final FunctionTarget initializer,
  final List<InstanceField> captures,
  final List<TypeParameterType> parameters,
  final List<InstanceField> environment,
);

final class CellShape(
  final ClassType type,
  final InstanceField value,
  final FunctionTarget initializer,
);
