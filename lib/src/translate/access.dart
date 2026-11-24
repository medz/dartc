import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'calls.dart';
import 'chains.dart';
import 'describe.dart';
import 'dynamics.dart';
import 'members.dart';
import 'records.dart';
import 'scope.dart';
import 'statics.dart';

/// Translates reading what a name after a dot tells.
final class AccessTranslator(
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
  final CallTranslator _calls,
  final StaticTranslator _statics,
  final DynamicTranslator _dynamics,
  final RecordTranslator _records,
  final ChainTranslator _chains,
) {
  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  /// Reads a field of a record, if [inner] is one.
  HirValue? _recordField(Expression inner) {
    final (target, name) = switch (inner) {
      PrefixedIdentifier(:final prefix, :final identifier) => (
        prefix,
        identifier.name,
      ),
      PropertyAccess(:final realTarget, :final propertyName) => (
        realTarget,
        propertyName.name,
      ),
      _ => (inner, ''),
    };
    final type = target.staticType;
    if (type == null || fieldIndex(type, name) == null) return null;
    return _records.field(_calls.object(target, inner), type, name);
  }

  /// Reads a property, or what a library or class declares.
  HirValue read(Expression inner) {
    if (_recordField(inner) case final found?) return found;
    switch (inner) {
      case PrefixedIdentifier(:final prefix, :final identifier)
          when prefix.staticType is DynamicType:
        return _dynamics.get(inner, _evaluator.value(prefix), identifier.name);
      case PropertyAccess(:final realTarget, :final propertyName)
          when realTarget.staticType is DynamicType:
        final object = _evaluator.value(realTarget);
        _chains.check(inner, object);
        return _dynamics.get(inner, object, propertyName.name);
      case PrefixedIdentifier(
            prefix: Expression(staticType: FunctionType()) &&
                final Expression function,
            identifier: SimpleIdentifier(name: 'call'),
          ) ||
          PropertyAccess(
            target: Expression(staticType: FunctionType()) &&
                final Expression function,
            propertyName: SimpleIdentifier(name: 'call'),
          ):
        final result = _evaluator.value(function);
        _chains.check(inner, result);
        return result;
      case PrefixedIdentifier(
        :final prefix,
        identifier: SimpleIdentifier(:final element),
      ):
        return isInstanceMember(element)
            ? _calls.property(inner, prefix, element!)
            : _statics.read(inner, element);
      case PropertyAccess(
        :final realTarget,
        propertyName: SimpleIdentifier(:final element),
      ):
        return isInstanceMember(element)
            ? _calls.property(inner, realTarget, element!)
            : _statics.read(inner, element);
      default:
        _unsupported(inner, describe(inner));
    }
  }
}
