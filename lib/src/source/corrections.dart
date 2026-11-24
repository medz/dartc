import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Another text for a part of a file.
typedef Edit = ({int offset, int end, String text});

/// The text of a file that the analyzer is given in place of [original], so
/// that it evaluates constants as the official compiler does.
final class CorrectedText(final String original, final List<Edit> _edits) {
  late final String text = () {
    final result = StringBuffer();
    var at = 0;
    for (final (:offset, :end, :text) in _edits) {
      result
        ..write(original.substring(at, offset))
        ..write(text);
      at = end;
    }
    return '$result${original.substring(at)}';
  }();

  /// Where in [original] is what is at [offset] of [text], or where the edit
  /// that made it starts.
  int originalOffset(int offset) {
    var shift = 0;
    for (final edit in _edits) {
      final start = edit.offset + shift;
      if (offset < start) break;
      if (offset < start + edit.text.length) return edit.offset;
      shift += edit.text.length - (edit.end - edit.offset);
    }
    return offset - shift;
  }
}

/// What the analyzer takes to be unknown, though it is false for programs that
/// are not compiled to JavaScript.
final _unknown = RegExp(
  r'''fromEnvironment\(\s*['"]dart\.library\.js_(?:interop|util)['"]''',
);

/// The text to analyze in place of [content], whose resolved [unit] there is,
/// or null if it is right as it is.
CorrectedText? correctionsOf(CompilationUnit unit, String content) {
  final visitor = _Comparisons(content);
  unit.accept(visitor);
  final edits = [
    for (final match in _unknown.allMatches(content))
      if (!visitor.edits.any(
        (edit) => edit.offset < match.end && match.start < edit.end,
      ))
        (
          offset: match.start,
          end: match.end,
          text: match[0]!.replaceFirst('dart.library', 'none.library'),
        ),
    ...visitor.edits,
  ]..sort((a, b) => a.offset - b.offset);
  return edits.isEmpty ? null : CorrectedText(content, edits);
}

/// Finds the comparisons of numbers in constants. The analyzer tells `0.0` from
/// `-0.0`, and takes neither what is not a number nor integers right.
final class _Comparisons(final String _content)
    extends RecursiveAstVisitor<void> {
  final edits = <Edit>[];

  @override
  void visitBinaryExpression(BinaryExpression node) =>
      _replace(node, () => super.visitBinaryExpression(node));

  @override
  void visitMethodInvocation(MethodInvocation node) =>
      _replace(node, () => super.visitMethodInvocation(node));

  void _replace(Expression node, void Function() orElse) {
    if (!_isCompared(node) || !_isConstant(node)) return orElse();
    edits.add((offset: node.offset, end: node.end, text: _text(node)));
  }

  static bool _isCompared(Expression node) => switch (node) {
    BinaryExpression(
      :final operator,
      :final leftOperand,
      :final rightOperand,
    ) =>
      (operator.lexeme == '==' || operator.lexeme == '!=') &&
          _mayBeDouble(leftOperand) &&
          (_mayBeDouble(rightOperand) ||
              (rightOperand.staticType?.isDartCoreInt ?? false)),
    MethodInvocation(
      methodName: SimpleIdentifier(
        name: 'identical',
        element: Element(library: LibraryElement(isDartCore: true)),
      ),
      argumentList: ArgumentList(arguments: [final left, final right]),
    ) =>
      _mayBeDouble(left.argumentExpression) ||
          _mayBeDouble(right.argumentExpression),
    _ => false,
  };

  static bool _mayBeDouble(Expression node) {
    if (node is NullLiteral) return false;
    final type = node.staticType?.extensionTypeErasure;
    return type is DynamicType ||
        type is TypeParameterType ||
        type is InterfaceType &&
            (type.isDartCoreDouble ||
                type.isDartCoreNum ||
                type.isDartCoreObject ||
                type.isDartAsyncFutureOr ||
                type.element.name == 'Comparable');
  }

  static bool _isNumber(Expression node) {
    final type = node.staticType?.extensionTypeErasure;
    return type != null &&
        type.nullabilitySuffix == .none &&
        (type.isDartCoreDouble || type.isDartCoreNum || type.isDartCoreInt);
  }

  /// [node] as it is, but for what is in it.
  String _text(Expression node) {
    if (node is MethodInvocation) {
      final [left, right] = node.argumentList.arguments;
      final a = _part(left.argumentExpression);
      final b = _part(right.argumentExpression);
      return '($a is int && $b is double || $a is double && $b is int '
          '? false : identical($a, $b) || $a is double && $b is double '
          '&& ($a as double) != ($a as double) '
          '&& ($b as double) != ($b as double))';
    }
    node as BinaryExpression;
    final BinaryExpression(:leftOperand, :rightOperand) = node;
    final a = _part(leftOperand), b = _part(rightOperand);
    final isEqual = _isNumber(leftOperand) && _isNumber(rightOperand)
        ? '($a <= $b && $a >= $b)'
        : '($a is num && $b is num '
              '? ($a as num) <= ($b as num) && ($a as num) >= ($b as num) '
              ': $a == $b)';
    return node.operator.lexeme == '==' ? isEqual : '!$isEqual';
  }

  String _part(Expression node) {
    final inner = _Comparisons(_content);
    node.accept(inner);
    // Those in constants are so inside too.
    final text = CorrectedText(_content.substring(node.offset, node.end), [
      for (final edit in inner.edits)
        (
          offset: edit.offset - node.offset,
          end: edit.end - node.offset,
          text: edit.text,
        ),
    ]).text;
    return '($text)';
  }

  /// Whether [node] is evaluated when compiling. What is evaluated then has no
  /// effects, and can be written twice.
  static bool _isConstant(Expression node) {
    if (node.inConstantContext) return true;
    for (AstNode? at = node; at != null; at = at.parent) {
      switch (at.parent) {
        case FunctionBody():
          return false;
        case FormalParameterDefaultClause() ||
            ConstantPattern() ||
            RelationalPattern() ||
            EnumConstantArguments():
          return true;
        case ConstructorDeclaration(:final constKeyword):
          return constKeyword != null;
        case PrimaryConstructorBody(:final parent):
          return _hasConstants(parent);
        case FieldDeclaration(:final isStatic, :final parent):
          return !isStatic && _hasConstants(parent);
      }
    }
    return false;
  }

  /// Whether the class around [member] has constants.
  static bool _hasConstants(AstNode? member) {
    for (var at = member; at != null; at = at.parent) {
      if (at is! CompilationUnitMember) continue;
      final element = at.declaredFragment?.element;
      return element is InterfaceElement &&
          element.constructors.any((constructor) => constructor.isConst);
    }
    return false;
  }
}
