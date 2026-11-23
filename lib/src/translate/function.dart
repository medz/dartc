import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

/// Translates one function of [unit].
final class FunctionTranslator(final SourceUnit unit) {
  HirBlock _block = HirBlock();

  Never _unsupported(AstNode node, String what) =>
      throw CompileFailure([unit.problem(node, 'Not supported yet: $what.')]);

  HirFunction translate(FunctionDeclaration declaration) {
    final function = declaration.functionExpression;
    if (function.parameters?.parameters.isNotEmpty ?? false) {
      _unsupported(function.parameters!, 'parameters');
    }
    if (function.typeParameters case final parameters?) {
      _unsupported(parameters, 'type parameters');
    }
    final body = function.body, entry = _block;
    if (body.isAsynchronous || body.isGenerator) {
      _unsupported(body, 'async and generator functions');
    }
    switch (body) {
      case BlockFunctionBody(:final block):
        _statement(block);
      case ExpressionFunctionBody(:final expression):
        _effect(expression);
      default:
        _unsupported(body, 'a function without a body');
    }
    if (_block.terminator == null) _block.end(HirReturn());
    return HirFunction(declaration.name.lexeme, entry);
  }

  /// Ends the current block; what follows is translated but never runs.
  void _end(HirTerminator terminator) {
    _block.end(terminator);
    _block = HirBlock();
  }

  void _statement(Statement statement) {
    switch (statement) {
      case Block(:final statements):
        statements.forEach(_statement);
      case EmptyStatement():
        break;
      case ExpressionStatement(:final expression):
        _effect(expression);
      case ReturnStatement(expression: null):
        _end(HirReturn());
      default:
        _unsupported(statement, _describe(statement));
    }
  }

  /// Evaluates [expression] without using its value.
  void _effect(Expression expression) {
    final inner = expression.unParenthesized;
    if (inner is MethodInvocation && _isExit(inner)) {
      _end(HirExit(_int(inner.argumentList.arguments.single)));
      return;
    }
    _int(inner);
  }

  static bool _isExit(MethodInvocation call) {
    final target = call.target;
    if (target != null &&
        (target is! SimpleIdentifier || target.element is! PrefixElement)) {
      return false;
    }
    final element = call.methodName.element;
    return element is TopLevelFunctionElement &&
        element.name == 'exit' &&
        element.library.uri == Uri.parse('dart:io');
  }

  /// Evaluates [node] to an `int`.
  HirInstruction _int(AstNode node) {
    switch (node) {
      case ParenthesizedExpression(:final expression):
        return _int(expression);
      case IntegerLiteral():
        return _literal(node, negated: false);
      case PrefixExpression(:final operator, :final operand):
        if (operator.lexeme == '-' && operand is IntegerLiteral) {
          return _literal(operand, negated: true);
        }
        for (final known in HirIntPrefix.values) {
          if (known.symbol != operator.lexeme) continue;
          _checkInt(operand);
          return _block.add(HirIntUnary(known, _int(operand)));
        }
        _unsupported(node, 'operator ${operator.lexeme}');
      case BinaryExpression(
        :final operator,
        :final leftOperand,
        :final rightOperand,
      ):
        for (final known in HirIntOperator.values) {
          if (known.symbol != operator.lexeme) continue;
          _checkInt(leftOperand);
          _checkInt(rightOperand);
          final left = _int(leftOperand), right = _int(rightOperand);
          return _block.add(HirIntBinary(known, left, right));
        }
        _unsupported(node, 'operator ${operator.lexeme}');
      default:
        _unsupported(node, _describe(node));
    }
  }

  void _checkInt(Expression operand) {
    if (!(operand.staticType?.isDartCoreInt ?? false)) {
      _unsupported(operand, 'operands of type ${operand.staticType}');
    }
  }

  HirInstruction _literal(IntegerLiteral literal, {required bool negated}) {
    _checkInt(literal);
    final value = literal.parseIntValue(negated: negated);
    if (value == null) throw StateError('Unchecked literal $literal.');
    return _block.add(HirInt(value));
  }

  /// The kind of [node] in words, from its class name.
  static String _describe(AstNode node) => node.runtimeType
      .toString()
      .replaceFirst('Impl', '')
      .replaceAllMapped(
        RegExp('(?<!^)[A-Z]'),
        (match) => ' ${match[0]!.toLowerCase()}',
      )
      .toLowerCase();
}
