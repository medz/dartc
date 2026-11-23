import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'conversions.dart';
import 'scope.dart';
import 'types.dart';

/// Translates calls that stand for operations, in the runtime and the SDK.
final class OperationTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
) {
  static final _elements = {
    for (final element in HirElement.values)
      element.name[0].toUpperCase() + element.name.substring(1): element,
  };

  /// The result of [node], which calls the operation [name], if it has one.
  HirValue? call(MethodInvocation node, String name) {
    final arguments = node.argumentList.arguments;
    HirValue argument(int index, HirType type) =>
        _evaluator.valueAs(arguments[index].argumentExpression, type);
    for (final operator in HirUnaryOperator.values) {
      if (operator.name != name) continue;
      return _builder.add(HirUnary(operator, argument(0, operator.operand)));
    }
    if (name.startsWith('load')) {
      if (_elements[name.substring(4)] case final element?) {
        final array = argument(0, .reference), index = argument(1, .integer);
        return _builder.add(HirLoadElement(element, array, index));
      }
    }
    if (name.startsWith('store')) {
      if (_elements[name.substring(5)] case final element?) {
        final array = argument(0, .reference), index = argument(1, .integer);
        final value = argument(2, element.type);
        _builder.add(HirStoreElement(element, array, index, value));
        return null;
      }
    }
    switch (name) {
      case 'lengthOf':
        return _builder.add(HirLength(argument(0, .reference)));
      case 'newArray':
        final type = node.typeArgumentTypes!.single as InterfaceType;
        final class_ = type.element as ClassElement;
        return _newArray(node, class_, argument(0, .integer));
      case 'unsafeCast':
        final type = node.typeArgumentTypes!.single;
        return Conversions(_scope, _builder).coerce(
          argument(0, .reference),
          valueType(type) ??
              (throw _builder.unit.unsupported(node, 'a value of type $type')),
        );
      case 'coreClassNumber':
        final class_ = _coreClass(arguments.first);
        final level = _scope.levelOf(class_);
        return _builder.add(HirClassNumber(_scope.classAt(level)));
      case 'newCoreArray':
        final class_ = _coreClass(arguments.first);
        return _newArray(node, class_, argument(1, .integer));
    }
    final op = HirMachineOp.values.byName(name);
    final call = _builder.add(
      HirMachine(op, [
        for (final (i, type) in op.parameters.indexed) argument(i, type),
      ]),
    );
    if (op == .trap || op == .resume) _builder.end(HirUnreachable());
    return call.type == null ? null : call;
  }

  ClassElement _coreClass(Argument name) {
    final text = (name.argumentExpression as StringLiteral).stringValue!;
    return _builder.library.typeProvider.objectElement.library.getClass(text)!;
  }

  /// An array of [element] with the type arguments that [node] gives.
  HirValue _newArray(
    MethodInvocation node,
    ClassElement element,
    HirValue length,
  ) {
    final type = node.typeArgumentTypes!.single as InterfaceType;
    final array = _create(element, length);
    if (type.typeArguments.isNotEmpty) {
      final list =
          _scope.typeList(_builder, type.typeArguments) ??
          (throw _builder.unit.unsupported(node, 'these type arguments'));
      final field = _scope.argumentsOf(_scope.levelOf(element))!;
      _builder.add(HirStore(field, array, list));
    }
    return array;
  }

  HirValue _create(ClassElement element, HirValue length) {
    final class_ = _scope.createdClass(element);
    final array = _builder.call(HirNewArray(class_, length))!;
    for (final field in class_.fields) {
      if (field.type != .integer) continue;
      _builder.add(HirStore(field, array, _builder.add(HirConst(0))));
    }
    return array;
  }
}
