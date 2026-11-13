import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/interop.dart';
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
  final adapters = <(FunctionTarget, ast.AstNode, String), IrFunction>{};

  /// Supplies target-typed memory access to the SDK's checked array list view.
  FunctionTarget nativeArrayAccess(
    FunctionTarget enclosing,
    ast.AstNode site,
    ClassType array,
    FunctionTarget address, {
    required bool store,
  }) {
    final element = array.typeArguments.single;
    final compound =
        element is ClassType && element.nativeType is NativeCompoundType;
    final name = compound
        ? '<array-view>'
        : store
        ? '<array-store>'
        : '<array-load>';
    final declaration = (enclosing, site, name);
    if (adapters[declaration] case final body?) return body.target;
    final target = FunctionTarget(
      enclosing.library,
      name,
      compound ? element : .integer,
      compound
          ? [ValueType.object, .integer]
          : [array, .integer, if (store) .integer],
      kind: .closure,
      enclosing: enclosing,
      sourceOffset: site.offset,
      captures: [if (compound) array],
    );
    final entry = Block(target.parameterTypes);
    final arguments = entry.parameters.skip(target.argumentOffset).toList();
    if (compound) {
      // Array's SDK typed-data base is a pointer; the captured array owns its storage.
      final base = entry.emit(
        UncheckedCast(
          arguments[0],
          FfiTypes.pointer.instantiate([FfiTypes.voidType]),
        ),
      );
      final pointer = entry.emit(
        IntBinary(.add, entry.emit(PointerAddress(base)), arguments[1]),
      );
      entry.finish(
        Return(
          entry.emit(
            NativeView(element, address: pointer, owner: entry.parameters[1]),
          ),
        ),
      );
      adapters[declaration] = IrFunction(target, [entry]);
      return target;
    }
    final storage = FfiTypes.describe(element);
    final offset = entry.emit(
      IntBinary(.multiply, arguments[1], entry.emit(NativeSize(storage))),
    );
    final pointer = entry.emit(
      IntBinary(.add, entry.emit(DirectCall(address, [arguments[0]])), offset),
    );
    final access = entry.emit(
      store
          ? StoreNative(pointer, storage, arguments[2])
          : LoadNative(pointer, storage),
    );
    entry.emit(KeepAlive(arguments[0]));
    entry.finish(Return(store ? arguments[2] : access));
    adapters[declaration] = IrFunction(target, [entry]);
    return target;
  }

  /// Captures a native address in an ordinary Dart function with a fixed signature.
  FunctionTarget nativeFunction(
    FunctionTarget enclosing,
    ast.AstNode site,
    ValueType pointerType,
    FunctionType signature, {
    required bool isLeaf,
  }) {
    final declaration = (
      enclosing,
      site,
      isLeaf ? '<native-leaf-function>' : '<native-function>',
    );
    if (adapters[declaration] case final body?) return body.target;
    if (signature.freeTypeParameters.isNotEmpty ||
        signature.typeParameters.isNotEmpty ||
        signature.optionalPositional != 0 ||
        signature.named.isNotEmpty) {
      throw UnsupportedError(
        'asFunction requires a static positional function type.',
      );
    }
    final target = FunctionTarget(
      enclosing.library,
      '<native-function>',
      signature.result,
      signature.parameters,
      kind: .closure,
      enclosing: enclosing,
      sourceOffset: site.offset,
      captures: [pointerType],
    );
    final entry = Block(target.parameterTypes);
    final call = entry.emit(
      NativeCall(
        entry.parameters[1],
        entry.parameters.skip(target.argumentOffset),
        isLeaf: isLeaf,
      ),
    );
    if (!FfiTypes.canCall(call.signature, signature)) {
      throw ArgumentError('Incompatible Dart representation for asFunction.');
    }
    entry.finish(Return(call));
    adapters[declaration] = IrFunction(target, [entry]);
    return target;
  }

  /// Adapts a static extension target without inventing a virtual receiver.
  FunctionTarget extensionTearOff(
    Bindings bindings,
    FunctionTarget enclosing,
    ExtensionApplication application,
    ast.AstNode site,
    List<ValueType> defaultTemplates, {
    FunctionTarget? nativeTypeCheck,
  }) {
    final declaration = (enclosing, site, '<extension-tearoff>');
    if (adapters[declaration] case final body?) return body.target;
    final executable = application.executable;
    // Extraction may occur inside this same method's body. Reuse capture-free
    // substitution, but always freshen its method binders.
    final signature = executable.sourceSignature.rebind({
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
      sourceOffset: site.offset,
      declarationLocation: executable.target.declarationLocation,
      captures: [application.receiverType],
      typeParameters: signature.typeParameters,
      optionalPositional: signature.optionalPositional,
      namedParameters: signature.namedParameters,
    );
    final entry = Block(target.parameterTypes);
    final blocks = [entry];
    if (nativeTypeCheck != null) {
      if (application.receiverType case ClassType(
        typeArguments: [ClassType(typeArguments: [final FunctionType native])],
      )) {
        final representation = FfiTypes.dartSignature(native);
        entry.emit(
          DirectCall(nativeTypeCheck, [
            entry.emit(ReifyType(signature.result)),
            TypeConstant(representation),
          ]),
        );
        final leaf = Block(), ordinary = Block();
        entry.finish(
          Branch(
            entry.parameters[target.argumentOffset +
                signature.named['isLeaf']!.slot],
            Jump(leaf),
            Jump(ordinary),
          ),
        );
        for (final (block, isLeaf) in [(leaf, true), (ordinary, false)]) {
          final closure = block.emit(
            MakeClosure(
              nativeFunction(
                target,
                site,
                application.receiverType,
                representation,
                isLeaf: isLeaf,
              ),
              [entry.parameters[1]],
            ),
          );
          block.finish(Return(block.emit(TypeCast(closure, signature.result))));
          blocks.add(block);
        }
      } else {
        throw UnsupportedError(
          'asFunction requires a static native function type.',
        );
      }
    } else {
      final result = entry.emit(
        DirectCall(
          executable.target,
          [
            entry.parameters[1],
            ...entry.parameters.skip(target.argumentOffset),
          ],
          typeArguments: [
            ...application.typeArguments,
            ...signature.typeParameters,
          ],
        ),
      );
      entry.finish(
        result.type == ValueType.never ? Unreachable(result) : Return(result),
      );
    }
    adapters[declaration] = IrFunction(
      target,
      blocks,
      defaults: {
        for (final entry in bindings.defaults(executable.target).entries)
          entry.key - executable.sourceParameterOffset: entry.value,
      },
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
      final enclosing = fn.parent?.target ?? root;
      ValueType slot(Element? e) {
        if (e == null) return receiverType ?? root.owner!;
        final declared = switch (e) {
          VariableElement(:final type) => type,
          LocalFunctionElement(:final type) => type,
          _ => throw StateError('Unexpected lexical capture.'),
        };
        final type = bindings
            .valueType(declared, unit, fn.syntax)
            .substitute(bindings.typeEnvironment(enclosing));
        return boxed.contains(e)
            ? CellType(
                type,
                isLate: (e as VariableElement).isLate,
                isFinal: e.isLate && e.isFinal,
              )
            : type;
      }

      int? awaiterCapture;
      for (final (index, capture) in fn.captures.indexed) {
        if (capture is! VariableElement) continue;
        for (final annotation in capture.metadata.annotations) {
          final value = annotation.computeConstantValue();
          if (value?.type case dart.InterfaceType(element: final type)
              when type.library.isDartCore &&
                  type == type.library.getClass('pragma') &&
                  value!.getField('name')?.toStringValue() ==
                      'vm:awaiter-link') {
            // The VM selects the last marked variable in capture order.
            awaiterCapture = index;
          }
        }
      }

      fn.target = switch (fn.element) {
        final LocalFunctionElement element => bindings.target(
          element,
          unit,
          fn.syntax,
          enclosing: enclosing,
          sourceOffset: fn.syntax.offset,
          captures: fn.captures.map(slot),
          awaiterCapture: awaiterCapture,
        ),
        final LocalVariableElement element => FunctionTarget(
          root.library,
          '<initialize:${element.name}>',
          bindings
              .valueType(element.type, unit, fn.syntax)
              .substitute(bindings.typeEnvironment(enclosing)),
          const [],
          kind: .closure,
          enclosing: enclosing,
          sourceOffset: fn.syntax.offset,
          captures: fn.captures.map(slot),
          awaiterCapture: awaiterCapture,
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
    if (_current != null) {
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
        // Record getters have a resolved type but no declaration element.
        if (_current != null &&
            !node.isQualified &&
            !node.inDeclarationContext() &&
            (element == null && node.staticType != null ||
                element is ExecutableElement &&
                    element is! ConstructorElement &&
                    !element.isStatic &&
                    (isClassLike(element.enclosingElement) ||
                        isExtensionOwner(element.enclosingElement)))) {
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
