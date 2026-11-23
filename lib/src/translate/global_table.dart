import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'classes.dart';
import 'constant.dart';
import 'constant_table.dart';
import 'expression.dart';
import 'scope.dart';
import 'types.dart';

/// The program's top-level variables and static fields.
final class GlobalTable(
  final ProgramScope _scope,
  final Declarations _declarations,
  final ConstantTable _constants,

  /// Has work done later.
  final void Function(void Function() work) _schedule,
) {
  final _variables = <PropertyInducingElement, GlobalVariable>{};

  Iterable<HirGlobal> get globals => [
    for (final GlobalVariable(:global, :isSet) in _variables.values) ...[
      global,
      ?isSet,
    ],
  ];

  /// The functions that set variables before their first use.
  Iterable<HirFunction> get getters =>
      _variables.values.map((variable) => variable.getter).nonNulls;

  /// The variable [element], or null if the program does not declare it.
  GlobalVariable? of(PropertyInducingElement element) =>
      _variables[element] ?? _make(element);

  GlobalVariable? _make(PropertyInducingElement element) {
    final declared = _declarations[element];
    if (declared == null) return null;
    CompileFailure unsupported(String what) =>
        _declarations.unsupported(element, what);
    if (element.isLate) throw unsupported('late variables');
    final isExternal = switch (element) {
      FieldElement() => element.isExternal,
      TopLevelVariableElement() => element.isExternal,
      _ => false,
    };
    if (isExternal) throw unsupported('external variables');
    final type =
        valueType(element.type) ??
        (throw unsupported('a variable of type ${element.type}'));
    final (unit, node) = declared;
    final initializer = (node as VariableDeclaration).initializer;
    final name = element.displayName;
    final initial = _initial(type, initializer);
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
      () => _defineGetter(variable, unit, initializer!, element.isFinal),
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

  /// Evaluates [initializer] unless the variable is set already.
  void _defineGetter(
    GlobalVariable variable,
    SourceUnit unit,
    Expression initializer,
    bool isFinal,
  ) {
    final GlobalVariable(:global, :isSet!, :getter!) = variable;
    final builder = FunctionBuilder(unit, getter, const []);
    final exit = builder.join(initializer);
    builder.branch(
      builder.add(HirLoadGlobal(isSet)),
      () => builder.jump(exit),
      () {
        final expressions = ExpressionTranslator(_scope, builder);
        final value = expressions.valueAs(initializer, global.type);
        if (isFinal) {
          // Evaluating it may have set it already.
          final number = _scope.lateNumber(global.name);
          builder.throwIf(
            builder.add(HirLoadGlobal(isSet)),
            _scope.throwerOf(.late),
            [builder.add(HirConst(number))],
          );
        }
        builder
          ..add(HirStoreGlobal(global, value))
          ..add(HirStoreGlobal(isSet, builder.add(HirConst(true))))
          ..jump(exit);
      },
    );
    builder.enter(exit);
    builder.end(HirReturn(builder.add(HirLoadGlobal(global))));
    builder.finish();
  }
}
