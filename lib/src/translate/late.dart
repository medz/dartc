import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'scope.dart';

/// Where a variable that can be without a value keeps one.
sealed class const LateStorage() {
  HirValue isSet(FunctionBuilder builder);
  HirValue load(FunctionBuilder builder);

  /// Gives the variable a value.
  void store(FunctionBuilder builder, HirValue value);
}

/// A top-level variable or static field.
final class const GlobalStorage(final HirGlobal _value, final HirGlobal _isSet)
    extends LateStorage {
  @override
  HirValue isSet(FunctionBuilder builder) => builder.add(HirLoadGlobal(_isSet));

  @override
  HirValue load(FunctionBuilder builder) => builder.add(HirLoadGlobal(_value));

  @override
  void store(FunctionBuilder builder, HirValue value) => builder
    ..add(HirStoreGlobal(_value, value))
    ..add(HirStoreGlobal(_isSet, builder.add(HirConst(true))));
}

/// A field of [_object], or a local variable, whose cell that is.
final class const FieldStorage(
  final HirField _value,
  final HirField _isSet,
  final HirValue _object,
) extends LateStorage {
  @override
  HirValue isSet(FunctionBuilder builder) =>
      builder.add(HirLoad(_isSet, _object));

  @override
  HirValue load(FunctionBuilder builder) =>
      builder.add(HirLoad(_value, _object));

  @override
  void store(FunctionBuilder builder, HirValue value) => builder
    ..add(HirStore(_value, _object, value))
    ..add(HirStore(_isSet, _object, builder.add(HirConst(true))));
}

/// Uses a variable that can be without a value.
final class LateAccess(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final VariableElement _variable,
  final LateStorage _storage,
) {
  List<HirValue> _about(String what) {
    final kind = _variable is LocalVariableElement ? 'Local' : 'Field';
    final number = _scope.lateNumber(
      "$kind '${_variable.displayName}' has $what.",
    );
    return [_builder.add(HirConst(number))];
  }

  void _throwIfSet(String what) => _builder.throwIf(
    _storage.isSet(_builder),
    _scope.throwerOf(.late),
    _about(what),
  );

  /// Reads the variable, which nothing else gives a value.
  HirValue read() {
    final isUnset = _builder.add(HirUnary(.not, _storage.isSet(_builder)));
    final thrower = _scope.throwerOf(.late);
    _builder.throwIf(isUnset, thrower, _about('not been initialized'));
    return _storage.load(_builder);
  }

  void write(HirValue value) {
    if (_variable.isFinal) _throwIfSet('already been initialized');
    _storage.store(_builder, value);
  }

  /// Returns the variable's value, which [initialize] gives if nothing has
  /// before.
  void returnValue(HirValue Function(DartType type) initialize) {
    void finish() => _builder.end(HirReturn(_storage.load(_builder)));
    _builder.branch(_storage.isSet(_builder), finish, () {
      final value = initialize(_variable.type);
      // Evaluating it may have set it already.
      if (_variable.isFinal) _throwIfSet('been assigned during initialization');
      _storage.store(_builder, value);
      finish();
    });
  }
}
