import 'package:dartc/ir.dart';

import 'type_values.dart';

/// Owns one projection entry per nominal declaration, independent of callers.
///
/// Descriptors select their own entry. Each entry visits only that declaration's
/// ancestors; it never scans the compilation's unrelated classes or subclasses.
final class TypeRelations(
  final TypeValues values,
  Iterable<ClassType> declarations, {
  ClassType? recordStorage,
}) {
  final _declarations = <ClassType>{};
  final _targets = <(ClassType, int?), FunctionTarget>{};
  final _views = <(ClassType, int?), IrFunction>{};
  final _projectors = <ClassType, FunctionTarget>{};
  final _bodies = <ClassType, IrFunction>{};
  ClassType? _recordStorage;
  var _revision = 0;

  /// Increases when a declaration or executable entry is introduced.
  int get revision => _revision;
  ClassType? get recordStorage => _recordStorage;

  this {
    values.bindProjectors(projectorOf, () => _recordStorage);
    extend(
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
      ],
      recordStorage:
          recordStorage ??
          values.runtime?.program.classes
              .where((c) => c.recordStorage)
              .singleOrNull
              ?.type,
    );
  }

  /// Extends the nominal universe without replacing existing targets or bodies.
  bool extend(Iterable<ClassType> declarations, {ClassType? recordStorage}) {
    var changed = false;
    if (recordStorage != null && recordStorage != _recordStorage) {
      if (_recordStorage != null) {
        throw StateError('The compilation record carrier cannot change.');
      }
      _recordStorage = recordStorage;
      _bodies.remove(recordStorage);
      changed = true;
    }
    void add(ClassType value) {
      if (!_declarations.add(value.declaration)) return;
      changed = true;
      values.id(value.declaration);
      if (values.runtime != null) projectorOf(value.declaration);
      for (final type in [
        ?value.declaration.superclass,
        ...value.declaration.interfaces,
        ...value.declaration.typeParameters.map((p) => p.bound),
      ]) {
        type.referencedClasses.forEach(add);
      }
    }

    declarations.forEach(add);
    if (recordStorage != null) add(recordStorage);
    if (changed) _revision++;
    return changed;
  }

  FunctionTarget get test => values.entry(.typeSubtype);

  /// Ordinary runtime implementation, shared by every nominal projector.
  IrFunction get projection =>
      values.runtime!.program.implementationOf(values.runtime!.projection)
          as IrFunction;

  /// Current adapters and descriptor-owned projection bodies.
  Iterable<IrFunction> get functions {
    // Building a template can demand descriptors for further nominal types.
    while (_projectors.keys.any((type) => !_bodies.containsKey(type))) {
      for (final type in _projectors.keys.toList()) {
        _bodies.putIfAbsent(type, () => _projectorBody(type));
      }
    }
    return [..._bodies.values, for (final key in _targets.keys) _view(key)];
  }

  /// The shared code entry held by descriptors of [declaration].
  FunctionTarget projectorOf(ClassType declaration) =>
      _projectors.putIfAbsent(declaration.declaration, () {
        _revision++;
        return FunctionTarget(
          null,
          'project${_projectors.length}',
          TypeMetadata.type.nullable,
          TypeMetadata.projectorSignature.parameters,
        );
      });

  FunctionTarget viewOf(ClassType owner) => _project(owner, null);
  FunctionTarget argumentOf(ClassType owner, int index) {
    RangeError.checkValidIndex(index, owner.typeParameters);
    return _project(owner, index);
  }

  FunctionTarget _project(ClassType owner, int? index) =>
      _targets.putIfAbsent((owner, index), () {
        _revision++;
        return FunctionTarget(
          null,
          '${index == null ? 'view' : 'argument'}${_targets.length}',
          TypeMetadata.type.nullable,
          [TypeMetadata.type],
        );
      });

  IrFunction _view((ClassType, int?) key) => _views.putIfAbsent(key, () {
    final (owner, index) = key;
    final target = _targets[key]!;
    final entry = Block(target.parameterTypes);
    entry.finish(
      Return(
        entry.emit(
          DirectCall(
            index == null
                ? values.runtime!.projection
                : values.entry(.typeArgument),
            [
              ...entry.parameters,
              _int(values.id(owner)),
              if (index != null) _int(index),
            ],
          ),
        ),
      ),
    );
    return IrFunction(target, [entry]);
  });

  IrFunction _projectorBody(ClassType declaration) {
    final target = _projectors[declaration]!;
    final entry = Block(target.parameterTypes);
    final missing = Block()..finish(const Return(Constant.nullValue()));
    final blocks = [entry, missing];
    final [actual, shape, slot] = entry.parameters;
    final owners = <ClassType>{};
    void ancestors(ClassType type) {
      if (!owners.add(type.declaration)) return;
      if (type.superclass case final parent?) ancestors(parent);
      type.interfaces.forEach(ancestors);
    }

    ancestors(declaration);
    Value build(Block block, ValueType type) => values.build(
      block,
      type,
      {
        for (final (i, parameter) in declaration.typeParameters.indexed)
          if (type.freeTypeParameters.contains(parameter))
            parameter: _part(block, actual, i),
      },
      shift: (value, count) => block.emit(
        DirectCall(values.entry(.typeShift), [value, _int(count), _int(0)]),
      ),
    );
    var current = entry;
    for (final owner in owners) {
      final view = declaration.asInstanceOf(owner)!;
      final found = Block(),
          next = Block(),
          whole = Block(),
          argument = Block();
      blocks.addAll([found, next, whole, argument]);
      _equal(current, shape, _int(values.id(owner)), found, next);
      found.finish(
        Branch(
          found.emit(IntBinary(.lessThan, slot, _int(0))),
          Jump(whole),
          Jump(argument),
        ),
      );
      whole.finish(
        Return(
          owner == declaration && declaration != _recordStorage
              ? actual
              : build(whole, view),
        ),
      );
      var selected = argument;
      for (final (i, type) in view.typeArguments.indexed) {
        final yes = Block(), no = Block();
        blocks.addAll([yes, no]);
        _equal(selected, slot, _int(i), yes, no);
        yes.finish(Return(build(yes, type)));
        selected = no;
      }
      selected.finish(Jump(missing));
      current = next;
    }
    current.finish(Jump(missing));
    return IrFunction(target, blocks);
  }

  static Constant _int(int value) => Constant.integer(value);
  static void _equal(Block block, Value a, Value b, Block yes, Block no) =>
      block.finish(Branch(block.emit(Equals(a, b)), Jump(yes), Jump(no)));
  Value _part(Block block, Value value, int index) {
    Value parts = block.emit(LoadField(TypeMetadata.parts, value));
    for (var i = 0; i < index; i++) {
      parts = block.emit(
        LoadField(TypeMetadata.tail, block.emit(NullCheck(parts))),
      );
    }
    return block.emit(
      LoadField(TypeMetadata.head, block.emit(NullCheck(parts))),
    );
  }
}
