// The pinned analyzer FFI verifier consumes its canonical AST API.
// ignore_for_file: experimental_member_use

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/listener.dart';

// ignore: implementation_imports
import 'package:analyzer/src/dart/ast/ast.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/element.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/type.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/diagnostic/diagnostic.dart' as diagnostics;
// ignore: implementation_imports
import 'package:analyzer/src/generated/ffi_verifier.dart';
// ignore: implementation_imports
import 'package:analyzer/src/generated/utilities_dart.dart';

/// Rechecks optional callbacks while retaining the analyzer's FFI obligations.
final class FfiCallbackChecks(
  final ResolvedUnitResult unit,
  final List<Diagnostic> errors,
) extends RecursiveAstVisitor2<void> {
  void check() {
    if (errors.any(
      (error) => error.diagnosticCode == diagnostics.mustBeASubtype,
    )) {
      unit.unit.accept2(this);
    }
  }

  @override
  void visitReceiverMethodInvocation(
    covariant internal.ReceiverMethodInvocationImpl node,
  ) {
    final element = switch (node.resolution) {
      internal.ExecutableInvocationResolution(:final element) => element,
      _ => null,
    };
    if (element is MethodElement &&
        element.library.uri == Uri.parse('dart:ffi') &&
        element ==
            element.library.getClass('Pointer')?.getMethod('fromFunction')) {
      _check(node, node.argumentList, node.typeArgumentTypes?.singleOrNull);
    }
    super.visitReceiverMethodInvocation(node);
  }

  @override
  void visitConstructorInvocation(
    covariant internal.ConstructorInvocationImpl node,
  ) {
    final constructor = node.constructorReference.element;
    if (constructor != null &&
        constructor.library.uri == Uri.parse('dart:ffi') &&
        constructor.enclosingElement ==
            constructor.library.getClass('NativeCallable')) {
      final type = node.staticType;
      if (type is internal.InterfaceTypeImpl) {
        _check(node, node.argumentList, type.typeArguments.singleOrNull);
      }
    }
    super.visitConstructorInvocation(node);
  }

  void _check(
    internal.AstNodeImpl invocation,
    internal.ArgumentListImpl arguments,
    internal.TypeImpl? native,
  ) {
    final argument = arguments.arguments2
        .where((argument) => argument is! internal.NamedArgumentImpl)
        .firstOrNull;
    if (argument == null || native is! internal.FunctionTypeImpl) return;
    bool shapeError(Diagnostic error) =>
        error.diagnosticCode == diagnostics.mustBeASubtype &&
        error.offset == argument.offset;
    if (!errors.any(shapeError)) return;
    final expression = argument.argumentExpression2;
    final original = expression.staticType;
    if (original is! internal.FunctionTypeImpl ||
        original.typeParameters.isNotEmpty ||
        !original.parameters.any((parameter) => parameter.isOptional)) {
      return;
    }
    final positional = original.parameters
        .where((parameter) => parameter.isPositional)
        .toList();
    var count = native.normalParameterTypes.length;
    if (native.normalParameterTypes.lastOrNull
        case internal.InterfaceTypeImpl(
          :final element,
          typeArguments: [
            internal.RecordTypeImpl(
              :final positionalFields,
              :final namedFields,
            ),
          ],
        )
        when element.library.uri == Uri.parse('dart:ffi') &&
            element == element.library.getClass('VarArgs') &&
            namedFields.isEmpty) {
      count += positionalFields.length - 1;
    }
    if (positional.length < count) return;
    final projected = internal.FunctionTypeImpl(
      typeParameters: const [],
      formalParameters: [
        for (final parameter in positional.take(count))
          internal.FormalParameterElementImpl.synthetic(
            parameter.name,
            parameter.type,
            ParameterKind.REQUIRED,
          ),
      ],
      returnType: original.returnType,
      nullabilitySuffix: .none,
    );
    final types =
        (unit.libraryElement as internal.LibraryElementImpl).typeSystem;
    if (!types.isSubtypeOf(original, projected)) return;
    final listener = RecordingDiagnosticListener();
    // shortcut: analyzer 14.7 rejects optional callbacks, remove when its FFI shape check accepts function subtypes.
    try {
      expression.setPseudoExpressionStaticType(projected);
      invocation.accept2(
        FfiVerifier(
          types,
          DiagnosticReporter(listener, unit.unit.declaredFragment!.source),
          strictCasts: unit.analysisOptions.strictCasts,
        ),
      );
    } finally {
      expression.setPseudoExpressionStaticType(original);
    }
    final checked = listener.diagnostics.where(
      (error) => error.severity == .error,
    );
    if (checked.any(shapeError)) return;
    errors.removeWhere(shapeError);
    errors.addAll(checked);
  }
}
