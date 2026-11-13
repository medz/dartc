import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';
import 'package:dartc/runtime/contracts.dart';

import 'analysis/session.dart';

/// Runtime contracts bound to the same definitions as ordinary Dart calls.
final class RuntimeDeclarations(
  Map<RuntimeRole, FunctionTarget> entries,
  Map<FunctionTarget, MemoryOperation> primitives,
  Iterable<FunctionTarget> nonAllocating,
  Iterable<FunctionTarget> systemFunctions, {
  final ClassType? stackContext,
}) {
  final Map<RuntimeRole, FunctionTarget> entries = .unmodifiable(entries);
  final Map<FunctionTarget, MemoryOperation> primitives = .unmodifiable(
    primitives,
  );
  final List<FunctionTarget> nonAllocating = .unmodifiable(nonAllocating);
  final Set<FunctionTarget> systemFunctions = .unmodifiable(systemFunctions);

  /// Reads trusted annotations while their owning analysis session is open.
  factory resolve(
    CheckedLibraries input,
    Iterable<ResolvedLibraryResult> libraries,
    FunctionTarget? Function(ExecutableElement) targetFor,
    ClassType Function(InterfaceElement, ResolvedUnitResult, ast.AstNode)
    classFor,
  ) {
    final visitor = _RuntimeDeclarations(input, libraries, targetFor, classFor);
    return .new(
      visitor.entries,
      visitor.primitives,
      visitor.nonAllocating,
      visitor.systemFunctions,
      stackContext: visitor.stackContext,
    );
  }
}

final class _RuntimeDeclarations(
  final CheckedLibraries input,
  Iterable<ResolvedLibraryResult> libraries,
  final FunctionTarget? Function(ExecutableElement) targetFor,
  final ClassType Function(InterfaceElement, ResolvedUnitResult, ast.AstNode)
  classFor,
) extends RecursiveAstVisitor<void> {
  this {
    if (input.runtimeContracts == null) return;
    for (final library in libraries) {
      for (final source in library.units) {
        if (!input.runtimeSources.contains(source.uri)) continue;
        unit = source;
        source.unit.accept(this);
      }
    }
  }

  final entries = <RuntimeRole, FunctionTarget>{};
  final primitives = <FunctionTarget, MemoryOperation>{};
  final nonAllocating = <FunctionTarget>[];
  final systemFunctions = <FunctionTarget>{};
  ClassType? stackContext;
  late ResolvedUnitResult unit;

  @override
  void visitAnnotation(ast.Annotation node) {
    final element = switch (node.parent) {
      ast.ClassDeclaration(:final declaredFragment) =>
        declaredFragment?.element,
      ast.FunctionDeclaration(:final declaredFragment) =>
        declaredFragment?.element,
      ast.MethodDeclaration(:final declaredFragment) =>
        declaredFragment?.element,
      _ => null,
    };
    final value = input.annotationValue(unit, node);
    if (value?.type case dart.InterfaceType(:final element)
        when element.library.uri != input.runtimeContracts) {
      return;
    }
    final type = value?.type;
    if (type is! dart.InterfaceType) return;
    final source = type.element.library;
    if (type.element == source.getClass('StackContext')) {
      if (element is! ClassElement || stackContext != null) {
        throw ArgumentError('Expected one runtime stack context interface.');
      }
      stackContext = classFor(element, unit, node);
      return;
    }
    if (element is! ExecutableElement) return;
    final isEntry = type.element == source.getClass('RuntimeEntry');
    final isPrimitive = type.element == source.getClass('Primitive');
    final noAllocation = type.element == source.getClass('NonAllocating');
    final system = type.element == source.getClass('SystemNative');
    if (!isEntry && !isPrimitive && !noAllocation && !system) return;
    final target = targetFor(element);
    if (target == null) return;
    if (system) {
      if (!element.isExternal || !systemFunctions.add(target)) {
        throw ArgumentError('Invalid system declaration: ${target.name}');
      }
      return;
    }
    if (noAllocation) {
      nonAllocating.add(target);
      return;
    }
    var enumeration = value!.getField(isEntry ? 'role' : 'operation');
    int? index;
    while (enumeration != null && index == null) {
      index = enumeration.getField('index')?.toIntValue();
      enumeration = enumeration.getField('(super)');
    }
    if (index == null ||
        index < 0 ||
        index >=
            (isEntry
                ? RuntimeRole.values.length
                : MemoryOperation.values.length)) {
      throw ArgumentError('Invalid runtime annotation.');
    }
    if (isEntry) {
      final role = RuntimeRole.values[index];
      if (entries.containsKey(role)) {
        throw ArgumentError('Repeated runtime entry: $role');
      }
      entries[role] = target;
    } else {
      if (!element.isExternal || primitives.containsKey(target)) {
        throw ArgumentError('Invalid primitive declaration: ${target.name}');
      }
      primitives[target] = MemoryOperation.values[index];
    }
  }
}
