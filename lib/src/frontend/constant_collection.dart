// The pinned evaluator uses the canonical analyzer AST and constant states.
// ignore_for_file: experimental_member_use, implementation_imports

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart' show DynamicType;
import 'package:analyzer/src/dart/constant/evaluation.dart';
import 'package:analyzer/src/dart/constant/potentially_constant.dart';
import 'package:analyzer/src/dart/constant/value.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/diagnostic/diagnostic.dart' as diag;

/// Builds a constant collection while checking each inserted value.
final class ConstantCollection(
  final TypedLiteral literal,
  final ConstantVisitor evaluator,
  final LibraryElementImpl library,
) {
  final _list = literal is ListLiteral ? <DartObjectImpl>[] : null;
  final _set = literal is SetOrMapLiteral && literal.isSet
      ? <DartObjectImpl>{}
      : null;
  final _map = literal is SetOrMapLiteral && literal.isMap
      ? <DartObjectImpl, DartObjectImpl>{}
      : null;
  late final _type = literal.staticType as InterfaceTypeImpl;

  Constant evaluate() {
    try {
      if (!literal.isConst) {
        _fail(literal, switch (literal) {
          ListLiteral() => diag.missingConstInListLiteral,
          SetOrMapLiteral(isSet: true) => diag.missingConstInSetLiteral,
          _ => diag.missingConstInMapLiteral,
        });
      }
      final elements = switch (literal) {
        ListLiteral(:final elements2) => elements2,
        SetOrMapLiteral(:final elements2) => elements2,
      };
      for (final element in elements) {
        _checkTypes(element);
        _add(element);
      }
      final state = switch (literal) {
        ListLiteral() => ListState(
          elementType: _type.typeArguments.single,
          elements: _list!,
        ),
        SetOrMapLiteral(isSet: true) => SetState(
          elementType: _type.typeArguments.single,
          elements: _set!,
        ),
        _ => MapState(
          keyType: _type.typeArguments[0],
          valueType: _type.typeArguments[1],
          entries: _map!,
        ),
      };
      return DartObjectImpl(library.typeSystem, _type, state);
    } on _Invalid catch (error) {
      return error.constant;
    }
  }

  // Static errors share diagnostic codes with errors in evaluated values.
  void _checkTypes(CollectionElement element) {
    switch (element) {
      case Expression():
        _assignable(element.staticType as TypeImpl, 0, element);
      case NullAwareElement(:final value2):
        _assignable(
          library.typeSystem.promoteToNonNull(value2.staticType as TypeImpl),
          0,
          value2,
        );
      case MapLiteralEntry(:final key2, :final value2):
        for (final (expression, nullable, index) in [
          (key2, element.keyQuestion != null, 0),
          (value2, element.valueQuestion != null, 1),
        ]) {
          final type = expression.staticType as TypeImpl;
          _assignable(
            nullable ? library.typeSystem.promoteToNonNull(type) : type,
            index,
            expression,
          );
        }
      case IfElement(:final thenElement2, :final elseElement2):
        _checkTypes(thenElement2);
        if (elseElement2 != null) _checkTypes(elseElement2);
      case SpreadElement(:final expression2):
        final type = expression2.staticType as TypeImpl;
        if (type is DynamicType ||
            type.isBottom ||
            element.isNullAware && type.isDartCoreNull) {
          return;
        }
        final source = type.asInstanceOf(
          _map == null
              ? library.typeProvider.iterableElement
              : library.typeProvider.mapElement,
        );
        if (source == null) {
          _fail(
            expression2,
            _map == null ? diag.notIterableSpread : diag.notMapSpread,
          );
        }
        for (var i = 0; i < source.typeArguments.length; i++) {
          _assignable(source.typeArguments[i], i, expression2);
        }
      case ForElement():
        _fail(element, diag.constEvalForElement);
      default:
        throw UnsupportedError('Constant collection element: $element');
    }
  }

  void _assignable(TypeImpl type, int index, AstNode site) {
    final expected = _type.typeArguments[index];
    if (!library.typeSystem.isAssignableTo(type, expected)) {
      final diagnostic = switch (literal) {
        ListLiteral() => diag.listElementTypeNotAssignable,
        SetOrMapLiteral(isSet: true) => diag.setElementTypeNotAssignable,
        _ when index == 0 => diag.mapKeyTypeNotAssignable,
        _ => diag.mapValueTypeNotAssignable,
      };
      _fail(
        site,
        diagnostic.withArguments(actualType: type, expectedType: expected),
      );
    }
  }

  void _add(CollectionElement element) {
    switch (element) {
      case Expression():
        _element(_read(element), element);
      case NullAwareElement(:final value2):
        final value = _read(value2);
        if (!value.isNull) _element(value, value2);
      case MapLiteralEntry(:final key2, :final value2):
        final key = _read(key2);
        if (element.keyQuestion != null && key.isNull) {
          _potential(value2);
          return;
        }
        final value = _read(value2);
        if (element.valueQuestion != null && value.isNull) return;
        _entry(key, value, element);
      case IfElement(
        :final expression2,
        :final thenElement2,
        :final elseElement2,
      ):
        final condition = _read(expression2).toBoolValue();
        if (condition == null) _fail(expression2, diag.nonBoolCondition);
        final selected = condition ? thenElement2 : elseElement2;
        final skipped = condition ? elseElement2 : thenElement2;
        if (skipped != null) _potential(skipped);
        if (selected != null) _add(selected);
      case SpreadElement(:final expression2):
        final value = _read(expression2);
        if (element.isNullAware && value.isNull) return;
        if (_map != null) {
          final entries = value.toMapValue();
          if (entries == null) _fail(expression2, diag.constSpreadExpectedMap);
          for (final entry in entries.entries) {
            _entry(entry.key, entry.value, expression2);
          }
        } else {
          final items = value.toListValue() ?? value.toSetValue();
          if (items == null) {
            _fail(expression2, diag.constSpreadExpectedListOrSet);
          }
          for (final item in items) {
            _element(item, expression2);
          }
        }
      case ForElement():
        _fail(element, diag.constEvalForElement);
      default:
        throw UnsupportedError('Constant collection element: $element');
    }
  }

  DartObjectImpl _read(Expression expression) {
    final value = evaluator.evaluateConstant(expression);
    if (value is InvalidConstant) throw _Invalid(value);
    value as DartObjectImpl;
    if (value.isUnknown) {
      throw UnsupportedError('A constant collection value is unknown.');
    }
    return value;
  }

  void _potential(AstNode node) {
    final invalid = getNotPotentiallyConstants(
      node,
      featureSet: library.featureSet,
    );
    if (invalid.isNotEmpty) {
      _fail(invalid.first, switch (literal) {
        ListLiteral() => diag.nonConstantListElement,
        SetOrMapLiteral(isSet: true) => diag.nonConstantSetElement,
        _ => diag.nonConstantMapElement,
      });
    }
  }

  void _element(DartObjectImpl value, AstNode site) {
    if (_map != null) _fail(site, diag.expressionInMap);
    _typeCheck(value, _type.typeArguments.single, site);
    if (_list case final list?) {
      list.add(value);
    } else {
      _primitive(value, site);
      if (!_set!.add(value)) _fail(site, diag.equalElementsInConstSet);
    }
  }

  void _entry(DartObjectImpl key, DartObjectImpl value, AstNode site) {
    if (_map == null) _fail(site, diag.mapEntryNotInMap);
    _typeCheck(key, _type.typeArguments[0], site);
    _typeCheck(value, _type.typeArguments[1], site);
    _primitive(key, site);
    if (_map.containsKey(key)) _fail(site, diag.equalKeysInConstMap);
    _map[key] = value;
  }

  void _typeCheck(DartObjectImpl value, TypeImpl type, AstNode site) {
    if (!library.typeSystem.runtimeTypeMatch(value, type)) {
      _fail(site, diag.constEvalThrowsException);
    }
  }

  void _primitive(DartObjectImpl value, AstNode site) {
    if (!value.hasPrimitiveEquality(library.featureSet)) {
      _fail(site, diag.constEvalPrimitiveEquality);
    }
  }

  Never _fail(AstNode site, diag.LocatableDiagnostic diagnostic) =>
      throw _Invalid(
        InvalidConstant.forEntity(
          entity: site,
          locatableDiagnostic: diagnostic,
        ),
      );
}

final class _Invalid(final InvalidConstant constant) implements Exception;
