import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'captures.dart';
import 'classes.dart';
import 'constant.dart';
import 'constant_table.dart';
import 'late.dart';
import 'scope.dart';
import 'types.dart';

/// The program's top-level variables and static fields.
final class GlobalTable(
  final ProgramScope _scope,
  final Declarations _declarations,
  final ConstantTable _constants,

  /// Has work done later.
  final void Function(HirFunction function, void Function() work) _schedule,
) {
  final _variables = <PropertyInducingElement, GlobalVariable>{};

  Iterable<HirGlobal> get globals => [
    for (final GlobalVariable(:global, :isSet) in _variables.values) ...[
      global,
      ?isSet,
    ],
  ];

  /// The functions that read variables that may not be set yet.
  Iterable<HirFunction> get getters =>
      _variables.values.map((variable) => variable.getter).nonNulls;

  /// The functions that read variables, with the variable of each.
  Iterable<(Element, HirFunction?)> get declared => [
    for (final MapEntry(:key, :value) in _variables.entries)
      (key, value.getter),
  ];

  /// The variable [element], or null if the program does not declare it.
  GlobalVariable? of(PropertyInducingElement element) =>
      _variables[element] ?? _make(element);

  GlobalVariable? _make(PropertyInducingElement element) {
    final declared = _declarations[element];
    if (declared == null) return null;
    CompileFailure unsupported(String what) =>
        _declarations.unsupported(element, what);
    final type =
        valueType(element.type) ??
        (throw unsupported('a variable of type ${element.type}'));
    final (unit, node) = declared;
    final initializer = (node as VariableDeclaration).initializer;
    final name = element.displayName;
    final initial = element.isLate && initializer == null
        ? null
        : _initial(type, initializer);
    if (initial != null) {
      final global = HirGlobal(name, type, initial.value);
      return _variables[element] = GlobalVariable(global);
    }
    final variable = GlobalVariable(
      HirGlobal(name, type, switch (type) {
        .integer => 0,
        .float => 0.0,
        .boolean => false,
        .reference => null,
      }),
      HirGlobal('$name is set', .boolean, false),
      HirFunction(name, const [], type),
    );
    _variables[element] = variable;
    _schedule(
      variable.getter!,
      () => _defineGetter(variable, unit, node, element),
    );
    return variable;
  }

  /// What a variable starts with, if evaluating that does nothing else.
  Constant? _initial(HirType type, Expression? initializer) {
    final value = initializer?.unParenthesized;
    switch (value) {
      case null:
        return Constant(null);
      case IntegerLiteral() when type != .reference:
        return Constant(integerLiteral(value, isNegated: false));
      case PrefixExpression(
            operator: Token(lexeme: '-'),
            operand: final IntegerLiteral operand,
          )
          when type != .reference:
        return Constant(integerLiteral(operand, isNegated: true));
      case Literal() ||
          PrefixExpression(operand: Literal()) ||
          InstanceCreationExpression(isConst: true):
        break;
      case Identifier(:final element) when constantVariable(element) != null:
        break;
      default:
        return null;
    }
    return _constants.of(type, value.computeConstantValue()?.value);
  }

  /// Reads [variable], evaluating its initializer if nothing set it.
  void _defineGetter(
    GlobalVariable variable,
    SourceUnit unit,
    VariableDeclaration node,
    PropertyInducingElement element,
  ) {
    final GlobalVariable(:global, :isSet!, :getter!) = variable;
    final builder = FunctionBuilder(
      unit,
      getter,
      const [],
      returnType: element.type,
      captures: _scope.capturesOf(declarationOf(node)),
      cellClass: _scope.cellClass,
    );
    final storage = GlobalStorage(global, isSet);
    final access = LateAccess(_scope, builder, element, storage);
    if (node.initializer case final initializer?) {
      access.returnValue((type) => _scope.evaluate(builder, initializer, type));
    } else {
      builder.end(HirReturn(access.read()));
    }
    builder.finish();
  }
}
