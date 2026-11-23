import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'calls.dart';
import 'describe.dart';
import 'members.dart';
import 'scope.dart';
import 'statics.dart';
import 'types.dart';

/// Something that can be assigned, whose parts are evaluated already.
sealed class const Place() {
  /// The type of the values assigned.
  HirType get type;
}

final class const _Local(
  final VariableElement variable,
  @override final HirType type,
) extends Place;

/// A variable or setter of a library or class.
final class const _Static(
  final AstNode node,
  final Element? reader,
  final SetterElement writer,
  @override final HirType type,
) extends Place;

/// A property or element of [receiver], or of the superclass's part of `this`
/// where [class_] is null.
final class const _Member(
  final AstNode node,
  final HirValue receiver,
  final ClassElement? class_,
  final ExecutableElement? reader,
  final ExecutableElement writer,
  final List<HirValue> positions,
  @override final HirType type,
) extends Place;

/// Translates what assignments read and write.
final class PlaceTranslator(
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
  final CallTranslator _calls,
  final StaticTranslator _statics,
) {
  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  /// Evaluates the parts of [to], which [node] assigns.
  Place place(CompoundAssignmentExpression node, Expression to) {
    final writer = node.writeElement;
    if (writer is VariableElement && _builder.typeOf(writer) != null) {
      return _Local(writer, _builder.typeOf(writer)!);
    }
    Never reject() => _unsupported(to, 'assignment to ${describe(to)}');
    HirType typeOf(FormalParameterElement parameter) =>
        valueType(parameter.type) ??
        _unsupported(to, 'a value of type ${parameter.type}');
    if (writer is SetterElement &&
        writer.isStatic &&
        _statics.declares(writer)) {
      final type = typeOf(writer.formalParameters.single);
      return _Static(node, node.readElement, writer, type);
    }
    if (writer is! ExecutableElement || !isInstanceMember(writer)) reject();
    final Expression? target;
    switch (to) {
      case SimpleIdentifier():
        target = null;
      case PrefixedIdentifier(:final prefix):
        target = prefix;
      case PropertyAccess(:final realTarget, :final isNullAware) ||
          IndexExpression(:final realTarget, :final isNullAware):
        if (isNullAware) _unsupported(node, 'null-aware assignments');
        target = realTarget;
      default:
        reject();
    }
    final isSuper = target is SuperExpression;
    final receiver = target == null || isSuper
        ? _builder.receiver ?? reject()
        : _calls.object(target);
    final parameters = writer.formalParameters;
    final reader = node.readElement;
    return _Member(
      node,
      receiver,
      isSuper
          ? null
          : target == null
          ? _builder.receiverClass
          : classOf(target.staticType),
      reader is ExecutableElement ? reader : null,
      writer,
      [
        if (to is IndexExpression)
          _evaluator.valueAs(to.index, typeOf(parameters.first)),
      ],
      typeOf(parameters.last),
    );
  }

  HirValue read(Place place) => switch (place) {
    _Local(:final variable) => _builder.read(variable),
    _Static(:final node, :final reader) => _statics.read(node, reader),
    _Member(:final reader?, :final positions) => _use(
      place,
      reader,
      positions,
    )!,
    _Member(:final node) => _unsupported(node, describe(node)),
  };

  void write(Place place, HirValue value) {
    switch (place) {
      case _Local(:final variable):
        _builder.assign(variable, value);
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
  ) => place.class_ == null
      ? _calls.superMember(place.node, element, values)
      : _calls.invoke(
          place.node,
          place.receiver,
          place.class_!,
          element,
          values,
        );
}
