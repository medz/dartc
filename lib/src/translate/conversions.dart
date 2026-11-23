import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_provider.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'scope.dart';
import 'types.dart';

/// Adds conversions between the representations of values, and tests of types.
final class Conversions(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  TypeProvider get types => _builder.library.typeProvider;

  /// The value that [value] is, represented as [to].
  ///
  /// Where an object has to become a number, it is one.
  HirValue coerce(HirValue value, HirType to) {
    if (value.type == to) return value;
    if (to == .reference) return _box(value);
    if (value.type != .reference) {
      throw StateError('A ${value.type} is no $to.');
    }
    final field = _scope.boxClass(to).fields.single;
    return _builder.add(HirLoad(field, value));
  }

  HirValue _box(HirValue value) {
    if (value is HirConst) {
      return _builder.add(HirStatic(_scope.boxOf(value.value)));
    }
    if (value.type == .boolean) {
      return _builder.choose(
        value,
        .reference,
        () => _builder.add(HirStatic(_scope.boxOf(true))),
        () => _builder.add(HirStatic(_scope.boxOf(false))),
      );
    }
    final class_ = _scope.boxClass(value.type!);
    final box = _builder.create(class_);
    _builder.add(HirStore(class_.fields.single, box, value));
    return box;
  }

  HirValue isNull(HirValue value) =>
      _builder.add(HirCompare(.equal, value, _builder.add(HirNull())));

  HirValue _not(HirValue value) => _builder.add(HirUnary(.not, value));

  /// Whether [value] is of [type], or null if that cannot be tested yet.
  HirValue? isInstance(HirValue value, DartType type) {
    HirValue constant(bool value) => _builder.add(HirConst(value));
    if (isTop(type)) return constant(true);
    if (value.type != .reference) {
      final exact = switch (value.type!) {
        .integer => types.intType,
        .float => types.doubleType,
        _ => types.boolType,
      };
      return constant(_builder.library.typeSystem.isSubtypeOf(exact, type));
    }
    if (type is NeverType) {
      return type.nullabilitySuffix == .question
          ? isNull(value)
          : constant(false);
    }
    if (type.isDartCoreNull) return isNull(value);
    final HirTypeTest test;
    if (type is FunctionType) {
      test = _scope.functionTest(type);
    } else if (type.isDartCoreFunction) {
      test = _scope.functionTest(null);
    } else {
      final class_ = classOf(type);
      if (class_ == null) return null;
      if (type.isDartCoreObject && type.nullabilitySuffix == .none) {
        return _not(isNull(value));
      }
      test = _scope.testOf(class_);
    }
    return _builder.choose(
      isNull(value),
      .boolean,
      () => constant(type.nullabilitySuffix == .question),
      () => _builder.add(HirIsInstance(test, value)),
    );
  }

  /// [value], of type [from], as one of type [to], or null if that cannot be
  /// tested yet.
  ///
  /// Throws an error ending with [ending] where it is not.
  HirValue? cast(
    HirValue value,
    DartType from,
    DartType to, {
    String ending = '',
  }) {
    final representation = valueType(to);
    if (representation == null) return null;
    if (_builder.library.typeSystem.isSubtypeOf(from, to) &&
        from is! DynamicType) {
      return coerce(value, representation);
    }
    final fits = isInstance(value, to);
    if (fits == null) return null;
    final number = _scope.castNumber(
      "' is not a subtype of type '${describeType(to)}'$ending",
    );
    _builder.unless(fits, () {
      final object = coerce(value, .reference);
      _builder.call(
        HirCall(_scope.throwerOf(.wrongType), [
          object,
          _builder.add(HirConst(number)),
        ]),
      );
    });
    return coerce(value, representation);
  }
}
