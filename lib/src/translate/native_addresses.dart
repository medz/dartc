import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'calls.dart';
import 'native_types.dart';
import 'scope.dart';
import 'types.dart';

/// Translates `.address` of fields and elements that are numbers, which are
/// not read.
final class NativeAddresses(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
  final CallTranslator _calls,
) {
  Never _unsupported(AstNode node) =>
      throw _builder.unit.unsupported(node, 'this address');

  HirValue _number(int value) => _builder.add(HirConst(value));

  /// The pointer that [node] gives, if it is such an address.
  HirValue? of(Expression node) {
    final (target, element) = switch (node) {
      PropertyAccess(:final target, :final propertyName) => (
        target,
        propertyName.element,
      ),
      PrefixedIdentifier(:final prefix, :final identifier) => (
        prefix,
        identifier.element,
      ),
      _ => (null, null),
    };
    final owner = element?.enclosingElement;
    if (target == null || !NativeTypes.isFfi(owner)) return null;
    return switch (owner!.name) {
      'IntAddress' ||
      'DoubleAddress' ||
      'BoolAddress' => _place(node, target.unParenthesized),
      _ => null,
    };
  }

  HirValue _place(Expression node, Expression place) {
    final (base, offset) = switch (place) {
      IndexExpression() => _element(place),
      PropertyAccess(:final target?, :final propertyName) => _field(
        place,
        target,
        propertyName.element,
      ),
      PrefixedIdentifier(:final prefix, :final identifier) => _field(
        place,
        prefix,
        identifier.element,
      ),
      SimpleIdentifier(:final element) => _field(place, null, element),
      _ => _unsupported(place),
    };
    final types = (node.staticType! as InterfaceType).typeArguments;
    return _call('pointerInto', [
      _scope.typeList(_builder, types) ?? _unsupported(node),
      base,
      offset,
    ]);
  }

  /// A field of a struct or union, and where it starts.
  (HirValue, HirValue) _field(
    Expression place,
    Expression? target,
    Element? element,
  ) {
    if (element is! GetterElement) _unsupported(place);
    final variable = element.baseElement.variable;
    final owner = variable.enclosingElement;
    if (variable is! FieldElement || owner is! InterfaceElement) {
      _unsupported(place);
    }
    final field =
        _scope.natives.types.field(owner, variable) ?? _unsupported(place);
    final object = target == null
        ? _builder.receiver ?? _unsupported(place)
        : _calls.object(target, place);
    return (object, _number(field.offset));
  }

  /// A list or array, and where an element of it starts.
  (HirValue, HirValue) _element(IndexExpression place) {
    final target = place.realTarget, type = boundOf(target.staticType!);
    final object = _calls.object(target, place);
    final index = _evaluator.valueTo(
      place.index,
      _builder.library.typeProvider.intType,
    );
    if (type is! InterfaceType) _unsupported(place);
    // The official compiler does not check the index either.
    HirValue offset(HirValue size) =>
        _builder.add(HirIntBinary(.multiply, index, size));
    if (!NativeTypes.isFfi(type.element)) {
      return (object, offset(_call('elementSize', [object])));
    }
    final native = _scope.natives.types.of(type.typeArguments.single);
    if (native == null) _unsupported(place);
    return (object, offset(_number(native.size)));
  }

  HirValue _call(String name, List<HirValue> arguments) =>
      _builder.call(HirCall(_scope.runtime(name), arguments))!;
}
