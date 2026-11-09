import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'ffi.dart';

/// Binds explicit native annotations through the lowering declaration table.
final class ExportBindings(final Bindings bindings)
    extends RecursiveAstVisitor<void> {
  final functions = <FunctionTarget, NativeExport>{};
  final _names = <String>{};
  late ResolvedUnitResult unit;

  @override
  void visitAnnotation(ast.Annotation node) {
    if (node.element case ConstructorElement(:final enclosingElement)) {
      final library = enclosingElement.library;
      if (library.uri != _exportLibrary ||
          enclosingElement != library.getClass('Export')) {
        return;
      }
    }
    // Constant aliases can select the annotation's type as well as its fields.
    bindings.constantSafety.check(unit, node, syntax: node);
    final value = node.elementAnnotation?.computeConstantValue();
    final type = value?.type;
    if (type is! dart.InterfaceType) return;
    final library = type.element.library;
    if (library.uri != _exportLibrary ||
        type.element != library.getClass('Export')) {
      return;
    }
    final declaration = node.parent;
    if (declaration is! ast.FunctionDeclaration ||
        declaration.parent is! ast.CompilationUnit) {
      throw UnsupportedError('Native exports require top-level functions.');
    }
    final native = type.typeArguments.single;
    if (native is! dart.FunctionType ||
        native.nullabilitySuffix != .none ||
        native.typeParameters.isNotEmpty ||
        native.formalParameters.any((p) => !p.isRequiredPositional)) {
      throw UnsupportedError(
        'Native exports require a non-generic positional FFI function signature.',
      );
    }
    final signature = NativeSignature(
      nativeType(native.returnType),
      native.formalParameters.map((p) => nativeType(p.type)),
    );
    final target = bindings.target(
      declaration.declaredFragment!.element,
      unit,
      declaration,
    );
    final body = declaration.functionExpression.body;
    if (body.isAsynchronous ||
        body.isGenerator ||
        body is ast.EmptyFunctionBody ||
        target.kind != .function ||
        target.owner != null ||
        target.typeParameters.isNotEmpty ||
        target.signature.optionalSlots.isNotEmpty ||
        target.signature.namedParameters.isNotEmpty ||
        target.returnType != FfiTypes.valueType(signature.result) ||
        target.parameterTypes.length != signature.parameters.length ||
        target.parameterTypes.indexed.any(
          (p) => p.$2 != FfiTypes.valueType(signature.parameters[p.$1]),
        )) {
      throw ArgumentError(
        'Native exports require matching synchronous Dart parameter and result types.',
      );
    }
    final export = NativeExport(
      value!.getField('symbol')!.toStringValue() ?? target.name,
      signature,
    );
    if (functions.containsKey(target) || !_names.add(export.symbol)) {
      throw ArgumentError('Repeated native export: ${export.symbol}');
    }
    functions[target] = export;
  }
}

final _exportLibrary = Uri.parse('package:dartc/src/interop/annotation.dart');
