import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';

/// The free declarations of a function literal or named local function.
final class LocalClosure(
  final LocalFunctionElement element,
  final ast.FunctionExpression syntax,
  final LocalClosure? parent,
) {
  /// A null slot denotes the enclosing instance receiver.
  final captures = <Element?>{};

  /// The body and capture signature assigned after finding all writes.
  late final FunctionTarget target;
}

/// Resolves captures through intervening functions before their SSA graphs are built.
final class ClosurePlan() extends GeneralizingAstVisitor<void> {
  final functions = <LocalFunctionElement, LocalClosure>{};
  final boxed = <VariableElement>{};
  final _written = <VariableElement>{};
  LocalClosure? _current;
  bool _enableAssertions = false;

  /// Assigns lexical targets and storage types for all nested bodies in [regions].
  void prepare(
    ResolvedUnitResult unit,
    Bindings bindings,
    FunctionTarget root,
    Iterable<ast.AstNode> regions,
  ) {
    _enableAssertions = bindings.enableAssertions;
    for (final region in regions) {
      region.accept(this);
    }
    boxed.retainAll(_written);
    for (final fn in functions.values) {
      ValueType slot(Element? e) {
        if (e == null) return root.owner!;
        final declared = switch (e) {
          VariableElement(:final type) => type,
          LocalFunctionElement(:final type) => type,
          _ => throw StateError('Unexpected lexical capture.'),
        };
        final type = bindings.valueType(declared, unit, fn.syntax);
        return boxed.contains(e) ? CellType(type) : type;
      }

      fn.target = bindings.target(
        fn.element,
        unit,
        fn.syntax,
        enclosing: fn.parent?.target ?? root,
        sourceOffset: fn.syntax.offset,
        captures: fn.captures.map(slot),
      );
    }
  }

  @override
  void visitAssertStatement(ast.AssertStatement node) {
    if (_enableAssertions) super.visitAssertStatement(node);
  }

  @override
  void visitAssertInitializer(ast.AssertInitializer node) {
    if (_enableAssertions) super.visitAssertInitializer(node);
  }

  void _use(Element? element) {
    if (element is! LocalVariableElement &&
        element is! FormalParameterElement &&
        element is! LocalFunctionElement) {
      return;
    }
    for (
      var fn = _current;
      fn != null &&
          element != fn.element &&
          element!.enclosingElement != fn.element;
      fn = fn.parent
    ) {
      fn.captures.add(element);
      if (element is VariableElement) boxed.add(element);
    }
  }

  void _useReceiver() {
    for (var fn = _current; fn != null; fn = fn.parent) {
      fn.captures.add(null);
    }
  }

  @override
  void visitFunctionExpression(ast.FunctionExpression node) {
    final element = node.declaredFragment!.element as LocalFunctionElement;
    final enclosing = _current;
    _current = functions[element] = LocalClosure(element, node, enclosing);
    node.body.accept(this);
    _current = enclosing;
  }

  @override
  void visitExpression(ast.Expression node) {
    switch (node) {
      case ast.SimpleIdentifier(:final element):
        _use(element);
        if (_current != null &&
            !node.isQualified &&
            !node.inDeclarationContext() &&
            element is ExecutableElement &&
            element is! ConstructorElement &&
            !element.isStatic &&
            element.enclosingElement is ClassElement) {
          _useReceiver();
        }
      case ast.ThisExpression() || ast.SuperExpression():
        _useReceiver();
      case ast.CompoundAssignmentExpression(:final writeElement):
        if (writeElement is VariableElement) {
          _written.add(writeElement);
          _use(writeElement);
        } else if (writeElement is SetterElement && !writeElement.isStatic) {
          final place = switch (node) {
            ast.AssignmentExpression(:final leftHandSide) => leftHandSide,
            ast.PrefixExpression(:final operand) ||
            ast.PostfixExpression(:final operand) => operand,
            _ => null,
          };
          if (place is ast.SimpleIdentifier) _useReceiver();
        }
    }
    super.visitExpression(node);
  }

  @override
  void visitForEachPartsWithIdentifier(ast.ForEachPartsWithIdentifier node) {
    final element = node.identifier.element;
    if (element is VariableElement) {
      _written.add(element);
      _use(element);
    }
    super.visitForEachPartsWithIdentifier(node);
  }

  @override
  void visitAssignedVariablePattern(ast.AssignedVariablePattern node) {
    if (node.element case final VariableElement variable) {
      _written.add(variable);
      _use(variable);
    }
    super.visitAssignedVariablePattern(node);
  }
}
