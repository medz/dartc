import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'constant.dart';
import 'describe.dart';
import 'members.dart';
import 'scope.dart';
import 'types.dart';

/// Translates uses of what libraries and classes hold, rather than objects.
final class StaticTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  Never _unsupported(AstNode node) =>
      throw _builder.unit.unsupported(node, describe(node));

  /// Reads the constant, variable or getter [element].
  HirValue read(AstNode node, Element? element) {
    if (constantVariable(element) case final variable?) {
      final type = valueType(variable.type);
      final constant =
          _scope.constantOf(type, variable.computeConstantValue()) ??
          (throw _builder.unit.unsupported(
            node,
            'a constant of type ${variable.type}',
          ));
      return _builder.add(constant);
    }
    if (element is ExecutableElement &&
        (element is TopLevelFunctionElement || element is MethodElement) &&
        !isInstanceMember(element)) {
      if (element.typeParameters.isNotEmpty) {
        throw _builder.unit.unsupported(node, 'generic functions as values');
      }
      final object = _scope.functionObject(element) ?? _unsupported(node);
      return _builder.add(HirStatic(object));
    }
    if (element is! GetterElement || isInstanceMember(element)) {
      _unsupported(node);
    }
    final HirFunction? getter;
    if (element.isOriginVariable) {
      final variable = _scope.globalOf(element.variable) ?? _unsupported(node);
      getter = variable.getter;
      if (getter == null) return _builder.add(HirLoadGlobal(variable.global));
    } else {
      getter = _scope.functionOf(element) ?? _unsupported(node);
    }
    return _builder.call(HirCall(getter, const [])) ?? _unsupported(node);
  }

  /// Whether the program declares [setter].
  bool declares(SetterElement setter) => setter.isOriginVariable
      ? _scope.globalOf(setter.variable) != null
      : _scope.functionOf(setter) != null;

  /// Writes with a setter that the program declares.
  void write(SetterElement setter, HirValue value) {
    if (!setter.isOriginVariable) {
      _builder.call(HirCall(_scope.functionOf(setter)!, [value]));
      return;
    }
    final GlobalVariable(:global, :isSet) = _scope.globalOf(setter.variable)!;
    _builder.add(HirStoreGlobal(global, value));
    if (isSet == null) return;
    _builder.add(HirStoreGlobal(isSet, _builder.add(HirConst(true))));
  }
}
