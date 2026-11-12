import 'dart:ffi' show Void;

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'ffi.dart';

/// Binds native annotations through the shared Dart declaration table.
final class NativeBindings(final Bindings bindings)
    extends RecursiveAstVisitor<void> {
  final exports = <FunctionTarget, NativeExport>{};
  final imports = <FunctionTarget, NativeReference>{};
  final _names = <String>{};
  late ResolvedUnitResult unit;
  String? _assetId;

  /// Applies the defining library's asset default to all of its parts.
  void bind(ResolvedLibraryResult library) {
    _assetId = null;
    final root = library.units.singleWhere(
      (unit) => unit.libraryFragment == library.element.firstFragment,
    );
    for (final current in [
      root,
      ...library.units.where((unit) => unit != root),
    ]) {
      unit = current;
      unit.unit.accept(this);
    }
  }

  @override
  void visitAnnotation(ast.Annotation node) {
    if (node.element case ConstructorElement(:final enclosingElement)) {
      final library = enclosingElement.library;
      if (library.uri != _exportLibrary && library.uri != _ffiLibrary) {
        return;
      }
    }
    // Constant aliases can select the annotation's type as well as its fields.
    final value = bindings.constants.annotation(unit, node);
    final type = value?.type;
    if (type is! dart.InterfaceType) return;
    final library = type.element.library;
    if (library.uri == _ffiLibrary) {
      if (type.element == library.getClass('DefaultAsset')) {
        if (node.parent is! ast.LibraryDirective || _assetId != null) {
          throw ArgumentError('Expected one DefaultAsset on the library.');
        }
        _assetId = value!.getField('id')!.toStringValue()!;
      } else if (type.element == library.getClass('Native')) {
        _import(node, value!, type);
      }
      return;
    }
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
    if (native is! dart.FunctionType) {
      throw UnsupportedError(
        'Native exports require a non-generic positional FFI function signature.',
      );
    }
    final signature = nativeSignature(
      native,
      bind: (type) => bindings.valueType(type, unit, node),
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
        !FfiTypes.canExport(signature, target.signature)) {
      throw ArgumentError(
        'Native exports require matching synchronous Dart parameter and result types.',
      );
    }
    final export = NativeExport(
      value!.getField('symbol')!.toStringValue() ?? target.name,
      signature,
    );
    if (exports.containsKey(target) || !_names.add(export.symbol)) {
      throw ArgumentError('Repeated native export: ${export.symbol}');
    }
    exports[target] = export;
  }

  void _import(ast.Annotation node, DartObject value, dart.InterfaceType type) {
    final element = switch (node.parent) {
      ast.FunctionDeclaration(:final declaredFragment) =>
        declaredFragment?.element,
      ast.MethodDeclaration(:final declaredFragment) =>
        declaredFragment?.element,
      _ => null,
    };
    if ((element is! TopLevelFunctionElement && element is! MethodElement) ||
        !element!.isExternal ||
        !element.isStatic) {
      throw UnsupportedError(
        'Native imports require external top-level or static functions.',
      );
    }
    final native = type.typeArguments.single;
    final signature = switch (native) {
      dart.FunctionType() => nativeSignature(
        native,
        bind: (type) => bindings.valueType(type, unit, node),
      ),
      dart.DynamicType() => NativeSignature.types(
        element.returnType is dart.VoidType
            ? NativeTypeRef.of(Void)
            : nativeType(
                element.returnType,
                bind: (type) => bindings.valueType(type, unit, node),
              ),
        element.formalParameters.map(
          (p) => nativeType(
            p.type,
            bind: (type) => bindings.valueType(type, unit, node),
          ),
        ),
      ),
      _ => throw UnsupportedError('Native import signature: $native'),
    };
    final target = bindings.target(element, unit, node);
    if (!FfiTypes.canCall(signature, target.signature)) {
      throw ArgumentError('Incompatible Dart signature for Native.');
    }
    if (imports.containsKey(target)) {
      throw ArgumentError('Repeated Native annotation: ${element.name}');
    }
    imports[target] = NativeReference(
      value.getField('assetId')!.toStringValue() ??
          _assetId ??
          element.library.uri.toString(),
      value.getField('symbol')!.toStringValue() ?? element.name!,
      signature,
      isLeaf: value.getField('isLeaf')!.toBoolValue()!,
    );
  }
}

final _exportLibrary = Uri.parse('package:dartc/src/interop/annotation.dart');
final _ffiLibrary = Uri.parse('dart:ffi');
