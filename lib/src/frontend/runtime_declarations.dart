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
) {
  final Map<RuntimeRole, FunctionTarget> entries = .unmodifiable(entries);
  final Map<FunctionTarget, MemoryOperation> primitives = .unmodifiable(
    primitives,
  );
  final List<FunctionTarget> nonAllocating = .unmodifiable(nonAllocating);

  /// Reads trusted annotations while their owning analysis session is open.
  factory resolve(
    CheckedLibraries input,
    FunctionTarget Function(ExecutableElement, ResolvedUnitResult, ast.AstNode)
    targetFor,
  ) {
    final visitor = _RuntimeDeclarations(input, targetFor);
    return .new(visitor.entries, visitor.primitives, visitor.nonAllocating);
  }
}

final class _RuntimeDeclarations(
  final CheckedLibraries input,
  final FunctionTarget Function(
    ExecutableElement,
    ResolvedUnitResult,
    ast.AstNode,
  )
  targetFor,
) extends RecursiveAstVisitor<void> {
  this {
    if (input.runtimeContracts == null) return;
    for (final library in input.libraries) {
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
  late ResolvedUnitResult unit;

  @override
  void visitAnnotation(ast.Annotation node) {
    final element = switch (node.parent) {
      ast.FunctionDeclaration(:final declaredFragment) =>
        declaredFragment?.element,
      ast.MethodDeclaration(:final declaredFragment) =>
        declaredFragment?.element,
      _ => null,
    };
    if (element is! ExecutableElement) return;
    final value = input.annotationValue(unit, node);
    if (value?.type case dart.InterfaceType(:final element)
        when element.library.uri != input.runtimeContracts) {
      return;
    }
    final type = value?.type;
    if (type is! dart.InterfaceType) return;
    final source = type.element.library;
    final isEntry = type.element == source.getClass('RuntimeEntry');
    final isPrimitive = type.element == source.getClass('Primitive');
    final noAllocation = type.element == source.getClass('NonAllocating');
    if (!isEntry && !isPrimitive && !noAllocation) return;
    final target = targetFor(element, unit, node);
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
