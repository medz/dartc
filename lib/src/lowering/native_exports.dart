import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';

/// Binds explicit native annotations through the lowering declaration table.
final class ExportBindings(final Bindings bindings)
    extends RecursiveAstVisitor<void> {
  final functions = <FunctionTarget, NativeExport>{};
  final _names = <String>{};
  late ResolvedUnitResult unit;

  @override
  void visitAnnotation(ast.Annotation node) {
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
        !_isInt64(native.returnType) ||
        native.formalParameters.any(
          (p) => !p.isRequiredPositional || !_isInt64(p.type),
        )) {
      throw UnsupportedError(
        'Native exports currently require an Int64 Function(Int64, ...) signature.',
      );
    }
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
        target.returnType != .integer ||
        target.parameterTypes.any((type) => type != .integer) ||
        target.parameterTypes.length != native.formalParameters.length) {
      throw ArgumentError(
        'An Int64 export requires a synchronous positional int function.',
      );
    }
    final export = NativeExport(
      value!.getField('symbol')!.toStringValue() ?? target.name,
      .int64(native.formalParameters.length),
    );
    if (functions.containsKey(target) || !_names.add(export.symbol)) {
      throw ArgumentError('Repeated native export: ${export.symbol}');
    }
    functions[target] = export;
  }

  bool _isInt64(dart.DartType type) =>
      type is dart.InterfaceType &&
      type.nullabilitySuffix == .none &&
      type.element.library.uri == _ffiLibrary &&
      type.element == type.element.library.getClass('Int64');
}

final _exportLibrary = Uri.parse('package:dartc/src/export/annotation.dart');
final _ffiLibrary = Uri.parse('dart:ffi');
