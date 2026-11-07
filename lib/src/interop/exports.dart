import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/analyzer.dart';
import 'package:dartc/ir.dart';

import 'native_export.dart';

/// Binds export annotations to IR declarations and emits matching C headers.
final class NativeExports(Iterable<NativeExport> functions) {
  /// Native functions in declaration order.
  final List<NativeExport> functions = .unmodifiable(functions);

  this {
    final names = <String>{}, targets = <FunctionTarget>{};
    for (final function in this.functions) {
      if (!names.add(function.symbol) || !targets.add(function.function)) {
        throw ArgumentError('Repeated native export: ${function.symbol}');
      }
    }
  }

  /// Reads bound `Export<Int64 Function(...)>` annotations from checked input.
  ///
  /// Uses the annotation declaration's identity, including through import
  /// aliases. Rejects annotations on other declarations and incompatible types.
  static Future<NativeExports> read(
    CheckedLibraries input,
    IrProgram program,
  ) async {
    final session = input.libraries.first.session;
    final annotationLibrary = await session.getLibraryByUri(
      'package:dartc/export.dart',
    );
    if (annotationLibrary is! LibraryElementResult) return NativeExports([]);
    final annotation = annotationLibrary.element.exportNamespace.get2('Export');
    final ffi = await session.getLibraryByUri('dart:ffi');
    if (annotation is! ClassElement || ffi is! LibraryElementResult) {
      throw StateError('Native annotation or FFI declarations unavailable.');
    }
    final int64 = ffi.element.getClass('Int64')!;
    final visitor = _Exports(annotation, int64, program);
    for (final library in input.libraries) {
      for (final unit in library.units) {
        unit.unit.accept(visitor);
      }
    }
    return NativeExports(visitor.functions);
  }

  /// Writes declarations usable from both C and C++.
  void writeHeader(StringSink output) {
    output.writeln(
      '#pragma once\n#include <stdint.h>\n\n#ifdef __cplusplus\nextern "C" {\n#endif\n',
    );
    for (final function in functions) {
      function.writeDeclaration(output);
    }
    output.writeln('\n#ifdef __cplusplus\n}\n#endif');
  }
}

final class _Exports(
  final ClassElement annotation,
  final ClassElement int64,
  final IrProgram program,
) extends RecursiveAstVisitor<void> {
  final functions = <NativeExport>[];

  @override
  void visitAnnotation(ast.Annotation node) {
    final value = node.elementAnnotation?.computeConstantValue();
    final type = value?.type;
    if (type is! dart.InterfaceType || type.element != annotation) return;
    final declaration = node.parent;
    if (declaration is! ast.FunctionDeclaration ||
        declaration.parent is! ast.CompilationUnit) {
      throw UnsupportedError('Native exports require top-level functions.');
    }
    final native = type.typeArguments.single;
    bool isInt64(dart.DartType type) =>
        type is dart.InterfaceType &&
        type.element == int64 &&
        type.nullabilitySuffix == .none;
    if (native is! dart.FunctionType ||
        native.nullabilitySuffix != .none ||
        native.typeParameters.isNotEmpty ||
        !isInt64(native.returnType) ||
        native.formalParameters.any(
          (p) => !p.isRequiredPositional || !isInt64(p.type),
        )) {
      throw UnsupportedError(
        'Native exports currently require an Int64 Function(Int64, ...) signature.',
      );
    }
    final element = declaration.declaredFragment!.element;
    final body = program.functions
        .where(
          (f) =>
              f.target.library == element.library.uri &&
              f.target.owner == null &&
              f.target.name == element.name,
        )
        .singleOrNull;
    if (body == null ||
        body.bodyKind != .synchronous ||
        body.target.parameterTypes.length != native.formalParameters.length) {
      throw ArgumentError('Incompatible native export: ${element.name}');
    }
    functions.add(
      NativeExport.int64(
        body.target,
        value!.getField('symbol')!.toStringValue() ?? element.name!,
      ),
    );
  }
}
