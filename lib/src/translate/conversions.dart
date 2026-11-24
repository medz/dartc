import 'package:analyzer/dart/ast/ast.dart';
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
    return _builder.add(HirUnbox(field, value));
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
    return _builder.call(HirBox(_scope.boxClass(value.type!), value))!;
  }

  /// [left], or what [right] gives if that is null, represented as [type].
  HirValue ifNull(
    AstNode node,
    HirType type,
    HirValue left,
    HirValue Function() right,
  ) {
    if (left.type != .reference) return coerce(left, type);
    final exit = _builder.join(node, type);
    _builder.branch(
      isNull(left),
      () => _builder.jump(exit, right()),
      () => _builder.jump(exit, coerce(left, type)),
    );
    return _builder.enter(exit)!;
  }

  HirValue isNull(HirValue value) =>
      _builder.add(HirCompare(.equal, value, _builder.add(HirNull())));

  HirValue _not(HirValue value) => _builder.add(HirUnary(.not, value));

  /// Whether [value] is of [declared], or null if that cannot be tested yet.
  HirValue? isInstance(HirValue value, DartType declared) {
    final type = declared.extensionTypeErasure;
    HirValue constant(bool value) => _builder.add(HirConst(value));
    if (isTop(type)) return constant(true);
    if (value.type != .reference) {
      if (type is InterfaceType && plainType(type.element) == value.type) {
        return constant(true);
      }
      final exact = switch (value.type!) {
        .integer => types.intType,
        .float => types.doubleType,
        _ => types.boolType,
      };
      if (isOpen(type)) return isInstance(coerce(value, .reference), type);
      return constant(_builder.library.typeSystem.isSubtypeOf(exact, type));
    }
    if (type is NeverType) {
      return type.nullabilitySuffix == .question
          ? isNull(value)
          : constant(false);
    }
    if (type.isDartCoreNull) return isNull(value);
    if (!_isPlain(type)) {
      if (valueType(type) == null) return null;
      final wanted = _scope.typeValue(_builder, type);
      if (wanted == null) return null;
      return _builder.call(
        HirCall(_scope.runtime('isInstance'), [value, wanted]),
      );
    }
    if (type.isDartCoreObject) return _not(isNull(value));
    final test = _scope.testOf(classOf(type)!);
    return _builder.choose(
      isNull(value),
      .boolean,
      () => constant(type.nullabilitySuffix == .question),
      () => _builder.add(HirIsInstance(test, value)),
    );
  }

  /// Whether the class of an object tells if it is of [type].
  static bool _isPlain(DartType type) =>
      type is InterfaceType &&
      classOf(type) != null &&
      type.typeArguments.every(isTop);

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
    final system = _builder.library.typeSystem;
    if (system.isSubtypeOf(
          from.extensionTypeErasure,
          to.extensionTypeErasure,
        ) &&
        from is! DynamicType) {
      return coerce(value, representation);
    }
    final fits = isInstance(value, to);
    if (fits == null) return null;
    _builder.unless(fits, () {
      // The name of an open type is known only when the program runs.
      final isKnown = !isOpen(to);
      _builder.call(
        HirCall(_scope.runtime(isKnown ? 'throwCast' : 'throwCastTo'), [
          coerce(value, .reference),
          isKnown
              ? _builder.add(_scope.text(describeType(to)))
              : _scope.typeValue(_builder, to)!,
          _builder.add(_scope.text(ending)),
        ]),
      );
    });
    return coerce(value, representation);
  }
}
