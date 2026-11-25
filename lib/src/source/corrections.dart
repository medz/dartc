import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'corrected_text.dart';
import 'enum_names.dart';

/// The texts to analyze for [units] that need an overlay, keyed by path.
Map<String, CorrectedText> correctionsOf(
  List<ResolvedUnitResult> units,
  Map<String, String> environment,
) {
  late final enumName = unusedEnumNameField(units.map((unit) => unit.content));
  late final absentName = _unusedEnvironmentName(environment);
  return {
    for (final unit in units)
      unit.path: ?_correctionsOf(unit, () => enumName, () => absentName),
  };
}

String _unusedEnvironmentName(Map<String, String> environment) {
  const prefix = 'none.library.js_interop';
  var name = prefix;
  for (var suffix = 0; environment.containsKey(name); suffix++) {
    name = '$prefix$suffix';
  }
  return name;
}

CorrectedText? _correctionsOf(
  ResolvedUnitResult result,
  String Function() enumName,
  String Function() absentName,
) {
  final ResolvedUnitResult(:unit, :content) = result;
  final visitor = _Constants(content, absentName);
  unit.accept(visitor);
  final names = EnumNames(enumName, visitor._part);
  unit.declarations.accept(names);
  final edits = [...names.edits, ...visitor.edits]
    ..sort((a, b) => a.offset - b.offset);
  return edits.isEmpty
      ? null
      : CorrectedText(content, edits, enumNameFields: names.fields);
}

/// Corrects the analyzer's evaluation of constants.
final class _Constants(
  final String _content,
  final String Function() _absentName,
) extends RecursiveAstVisitor<void> {
  final edits = <Edit>[];

  @override
  void visitBinaryExpression(BinaryExpression node) =>
      _replace(node, () => super.visitBinaryExpression(node));

  @override
  void visitMethodInvocation(MethodInvocation node) =>
      _replace(node, () => super.visitMethodInvocation(node));

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.isConst || _isConstant(node)) {
      _environment(node.constructorName.element, node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    if (node.isConst || _isConstant(node)) {
      _environment(node.element, node.argumentList);
    }
    super.visitDotShorthandConstructorInvocation(node);
  }

  void _environment(ConstructorElement? constructor, ArgumentList arguments) {
    if (constructor case ConstructorElement(
      name: 'fromEnvironment',
      returnType: DartType(isDartCoreBool: true),
    )) {
      final argument = arguments.arguments.firstOrNull;
      // The analyzer treats web availability as unknown for a boolean read.
      if (argument case StringLiteral(
        stringValue: 'dart.library.js_util' || 'dart.library.js_interop',
      )) {
        edits.add((
          offset: argument.offset,
          end: argument.end,
          text: "'${_absentName()}'",
        ));
      }
    }
  }

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
    final inner = _Constants(_content, _absentName);
    node.accept(inner);
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
