import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';

/// The free declarations of a lexical function or lazy local initializer.
final class LocalClosure(
  final Element element,
  final ast.AstNode syntax,
  final LocalClosure? parent,
) {
  /// A null slot denotes the enclosing instance receiver.
  final captures = <Element?>{};

  /// The body and capture signature assigned after finding all writes.
  late final FunctionTarget target;
}

/// Resolves captures through intervening functions before their SSA graphs are built.
final class ClosurePlan() extends GeneralizingAstVisitor<void> {
  final functions = <Element, LocalClosure>{};
  final syntheticFunctions = <IrFunction>[];

  /// Adapts a static extension target without inventing a virtual receiver.
  FunctionTarget extensionTearOff(
    Bindings bindings,
    FunctionTarget enclosing,
    ExtensionApplication application,
    int offset,
    List<ValueType> defaultTemplates,
  ) {
    final executable = application.executable;
    // Extraction may occur inside this same method's body. Reuse capture-free
    // substitution, but always freshen its method binders.
    final signature = rebindFunctionType(executable.sourceSignature, {
      for (final (i, parameter) in executable.extensionParameters.indexed)
        parameter: application.typeArguments[i],
    }, defaultTemplates: defaultTemplates);
    final target = FunctionTarget(
      enclosing.library,
      '<extension-tearoff:${executable.target.name}>',
      signature.result,
      signature.parameters,
      kind: .closure,
      enclosing: enclosing,
      sourceOffset: offset,
      captures: [application.receiverType],
      typeParameters: signature.typeParameters,
      optionalPositional:
          signature.positionalCount - signature.requiredPositional,
      namedParameters: {
        for (final entry in signature.named.entries)
          entry.key: entry.value.required,
      },
    );
    final entry = Block(target.parameterTypes);
    final result = entry.emit(
      DirectCall(
        executable.target,
        [entry.parameters[1], ...entry.parameters.skip(target.argumentOffset)],
        typeArguments: [
          ...application.typeArguments,
          ...signature.typeParameters,
        ],
      ),
    );
    entry.finish(
      result.type == ValueType.never ? Unreachable(result) : Return(result),
    );
    syntheticFunctions.add(
      IrFunction(
        target,
        [entry],
        defaults: {
          for (final entry in bindings.defaults(executable.target).entries)
            entry.key - executable.sourceParameterOffset: entry.value,
        },
      ),
    );
    return target;
  }

  final boxed = <VariableElement>{};
  final _written = <VariableElement>{};
  // Synthetic initializers have no analyzer executable element. Track actual
  // lexical ownership so their expression-local declarations are not captures.
  final _owners = <Element, LocalClosure>{};
  LocalClosure? _current;
  bool _enableAssertions = false;

  /// Assigns lexical targets and storage types for all nested bodies in [regions].
  void prepare(
    ResolvedUnitResult unit,
    Bindings bindings,
    FunctionTarget root,
    Iterable<ast.AstNode> regions, {
    ValueType? receiverType,
  }) {
    _enableAssertions = bindings.enableAssertions;
    for (final region in regions) {
      region.accept(this);
    }
    boxed.removeWhere(
      (variable) => !variable.isLate && !_written.contains(variable),
    );
    for (final fn in functions.values) {
      if (fn.element case final LocalFunctionElement element) {
        bindings.registerTypeParameters(element.typeParameters);
      }
    }
    for (final fn in functions.values) {
      ValueType slot(Element? e) {
        if (e == null) return receiverType ?? root.owner!;
        final declared = switch (e) {
          VariableElement(:final type) => type,
          LocalFunctionElement(:final type) => type,
          _ => throw StateError('Unexpected lexical capture.'),
        };
        final type = bindings.valueType(declared, unit, fn.syntax);
        return boxed.contains(e)
            ? CellType(
                type,
                isLate: (e as VariableElement).isLate,
                isFinal: e.isLate && e.isFinal,
              )
            : type;
      }

      final enclosing = fn.parent?.target ?? root;
      fn.target = switch (fn.element) {
        final LocalFunctionElement element => bindings.target(
          element,
          unit,
          fn.syntax,
          enclosing: enclosing,
          sourceOffset: fn.syntax.offset,
          captures: fn.captures.map(slot),
        ),
        final LocalVariableElement element => FunctionTarget(
          root.library,
          '<initialize:${element.name}>',
          bindings.valueType(element.type, unit, fn.syntax),
          const [],
          kind: .closure,
          enclosing: enclosing,
          sourceOffset: fn.syntax.offset,
          captures: fn.captures.map(slot),
        ),
        _ => throw StateError('Unexpected lexical body.'),
      };
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
    // The analyzer leaves a local function's enclosing element null, so its
    // lexical owner comes from the same plan that supplies its target.
    final owner = element is LocalFunctionElement
        ? functions[element]?.parent?.element
        : _owners[element]?.element ?? element!.enclosingElement;
    for (
      var fn = _current;
      fn != null && element != fn.element && owner != fn.element;
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
  void visitVariableDeclaration(ast.VariableDeclaration node) {
    final element = node.declaredFragment!.element;
    _declare(element);
    if (node.isLate && node.initializer != null) {
      final enclosing = _current;
      _current = functions[element] = LocalClosure(element, node, enclosing);
      node.initializer!.accept(this);
      _current = enclosing;
    } else {
      super.visitVariableDeclaration(node);
    }
  }

  void _declare(Element element) {
    if (_current?.element is LocalVariableElement) {
      _owners[element] = _current!;
    }
  }

  @override
  void visitDeclaredIdentifier(ast.DeclaredIdentifier node) {
    _declare(node.declaredFragment!.element);
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitDeclaredVariablePattern(ast.DeclaredVariablePattern node) {
    for (
      PatternVariableElement? variable = node.declaredFragment!.element;
      variable != null;
      variable = variable.join
    ) {
      _declare(variable);
    }
    super.visitDeclaredVariablePattern(node);
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
            (isClassOrEnum(element.enclosingElement) ||
                element.enclosingElement is ExtensionElement)) {
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
