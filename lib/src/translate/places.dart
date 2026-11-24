import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'calls.dart';
import 'chains.dart';
import 'conversions.dart';
import 'describe.dart';
import 'dynamics.dart';
import 'late_locals.dart';
import 'members.dart';
import 'scope.dart';
import 'statics.dart';
import 'types.dart';

/// Something that can be assigned, whose parts are evaluated already.
sealed class const Place() {
  /// The type of the values assigned.
  DartType get type;
}

final class const _Local(
  final VariableElement variable,
  @override final DartType type,
) extends Place;

/// A variable or setter of a library or class.
final class const _Static(
  final AstNode node,
  final Element? reader,
  final SetterElement writer,
  @override final DartType type,
) extends Place;

/// A property called [name] of an object that can be anything, or an element
/// at [index].
final class const _Dynamic(
  final AstNode node,
  final HirValue object,
  final String name,
  final HirValue? index,
  @override final DartType type,
) extends Place;

/// A property or element of [receiver], or of the superclass's part of `this`
/// if [isSuper].
final class const _Member(
  final AstNode node,
  final HirValue receiver,
  final bool isSuper,
  final DartType? receiverType,
  final ExecutableElement? reader,
  final ExecutableElement writer,
  final List<HirValue> positions,
  @override final DartType type,
) extends Place;

/// Translates what assignments read and write.
final class PlaceTranslator(
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
  final CallTranslator _calls,
  final StaticTranslator _statics,
  final Conversions _conversions,
  final DynamicTranslator _dynamics,
  final LateTranslator _lates,
  final ChainTranslator _chains,
) {
  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  /// Evaluates the parts of [to], which [node] assigns.
  Place place(CompoundAssignmentExpression node, Expression to) {
    final writer = node.writeElement;
    if (writer is VariableElement && _builder.typeOf(writer) != null) {
      return _Local(writer, writer.type);
    }
    Never reject() => _unsupported(to, 'assignment to ${describe(to)}');
    DartType typeOf(FormalParameterElement parameter) =>
        valueType(parameter.type) != null
        ? parameter.type
        : _unsupported(to, 'a value of type ${parameter.type}');
    if (writer is SetterElement &&
        writer.isStatic &&
        _statics.declares(writer)) {
      final type = typeOf(writer.formalParameters.single);
      return _Static(node, node.readElement, writer, type);
    }
    final owner = switch (to) {
      PrefixedIdentifier(:final prefix) => prefix,
      PropertyAccess(:final realTarget) ||
      IndexExpression(:final realTarget) => realTarget,
      _ => null,
    };
    if (owner != null && owner.staticType is DynamicType) {
      return _dynamicPlace(to, owner);
    }
    if (writer is! ExecutableElement || !isInstanceMember(writer)) reject();
    final Expression? target;
    switch (to) {
      case SimpleIdentifier():
        target = null;
      case PrefixedIdentifier(:final prefix):
        target = prefix;
      case PropertyAccess(:final realTarget) ||
          IndexExpression(:final realTarget):
        target = realTarget;
      default:
        reject();
    }
    final isSuper = target is SuperExpression;
    final receiver = target == null || isSuper
        ? _builder.receiver ?? reject()
        : _calls.object(target, to);
    final parameters = writer.formalParameters;
    final reader = node.readElement;
    return _Member(
      node,
      receiver,
      isSuper,
      _calls.receiverType(target, to),
      reader is ExecutableElement ? reader : null,
      writer,
      [
        if (to is IndexExpression)
          _evaluator.valueTo(to.index, typeOf(parameters.first)),
      ],
      typeOf(parameters.last),
    );
  }

  Place _dynamicPlace(Expression to, Expression owner) {
    final object = _evaluator.value(owner);
    _chains.check(to, object);
    return _Dynamic(
      to,
      object,
      switch (to) {
        PrefixedIdentifier(:final identifier) => identifier.name,
        PropertyAccess(:final propertyName) => propertyName.name,
        _ => '',
      },
      to is IndexExpression
          ? _evaluator.value(to.index, placeholder: .reference)
          : null,
      owner.staticType!,
    );
  }

  HirValue read(Place place) => switch (place) {
    _Dynamic(:final node, :final object, :final name, index: null) =>
      _dynamics.get(node, object, name),
    _Dynamic(:final node, :final object, :final index?) => _dynamics.operate(
      node,
      object,
      '[]',
      [index],
    ),
    _Local(:final variable) => _lates.read(variable) ?? _builder.read(variable),
    _Static(:final node, :final reader) => _statics.read(node, reader),
    _Member(:final reader?, :final positions) => _use(
      place,
      reader,
      positions,
    )!,
    _Member(:final node) => _unsupported(node, describe(node)),
  };

  /// Assigns [given], which is of the type of [place].
  void write(Place place, HirValue given) {
    final value = _conversions.coerce(given, valueType(place.type)!);
    switch (place) {
      case _Local(:final variable):
        if (!_lates.write(variable, value)) _builder.assign(variable, value);
      case _Dynamic(:final node, :final object, :final name, index: null):
        _dynamics.set(node, object, name, value);
      case _Dynamic(:final node, :final object, :final index?):
        _dynamics.operate(node, object, '[]=', [index, value]);
      case _Static(:final writer):
        _statics.write(writer, value);
      case _Member(:final writer, :final positions):
        _use(place, writer, [...positions, value]);
    }
  }

  HirValue? _use(
    _Member place,
    ExecutableElement element,
    List<HirValue> values,
  ) => place.isSuper
      ? _calls.superMember(place.node, element, values)
      : _calls.invoke(
          place.node,
          place.receiver,
          place.receiverType,
          element,
          values,
        );
}
