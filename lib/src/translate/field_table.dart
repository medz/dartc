import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'captures.dart';
import 'classes.dart';
import 'conversions.dart';
import 'late.dart';
import 'levels.dart';
import 'native_fields.dart';
import 'native_types.dart';
import 'scope.dart';

/// Uses the fields of objects.
final class FieldTable(
  final ProgramScope _scope,
  final Declarations _declarations,
  final ClassTable _classes,
) {
  final _getters = <(Level, FieldElement), HirFunction>{};

  /// The functions that initialize `late` fields.
  Iterable<HirFunction> get functions => _getters.values;

  HirValue load(
    FunctionBuilder builder,
    Level level,
    FieldElement element,
    HirValue object,
  ) {
    if (_native(level, element) case final field?) {
      return NativeFields(_scope, builder).load(field, object);
    }
    final (:value, :isSet) = _classes.fieldOf(level, element);
    if (isSet == null) return builder.add(HirLoad(value, object));
    if (!element.hasInitializer) {
      final storage = FieldStorage(value, isSet, object);
      return LateAccess(_scope, builder, element, storage).read();
    }
    return builder.call(HirCall(_getterOf(level, element), [object]))!;
  }

  void store(
    FunctionBuilder builder,
    Level level,
    FieldElement element,
    HirValue object,
    HirValue given,
  ) {
    if (_native(level, element) case final field?) {
      return NativeFields(_scope, builder).store(field, object, given);
    }
    final (:value, :isSet) = _classes.fieldOf(level, element);
    if (isSet == null) {
      builder.add(HirStore(value, object, given));
    } else {
      final storage = FieldStorage(value, isSet, object);
      LateAccess(_scope, builder, element, storage).write(given);
    }
  }

  /// How C has the field [element], if it does.
  NativeField? _native(Level level, FieldElement element) => element.isExternal
      ? _scope.natives.types.field(level.element, element)
      : null;

  HirFunction _getterOf(Level level, FieldElement element) =>
      _getters[(level, element)] ??= () {
        final (:value, :isSet) = _classes.fieldOf(level, element);
        final function = HirFunction(
          '${level.element.displayName}.${element.displayName}',
          [.reference],
          value.type,
        );
        _scope.schedule(() => _define(function, level, element));
        return function;
      }();

  void _define(HirFunction function, Level level, FieldElement element) {
    final (:value, :isSet) = _classes.fieldOf(level, element);
    final (unit, node) = _declarations[element]!;
    final builder = FunctionBuilder(
      unit,
      function,
      const [],
      ownLevel: level,
      returnType: element.type,
      captures: _scope.capturesOf(declarationOf(node)),
      cellClass: _scope.cellClass,
    );
    final storage = FieldStorage(value, isSet!, builder.inputs.single);
    LateAccess(_scope, builder, element, storage).returnValue((type) {
      final initializer = (node as VariableDeclaration).initializer!;
      final given = _scope.evaluate(builder, initializer, type);
      return Conversions(_scope, builder).coerce(given, value.type);
    });
    builder.finish();
  }
}
