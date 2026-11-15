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
  Map<FunctionTarget, SystemLibrary> systemFunctions, {
  Map<FunctionTarget, FunctionTarget> aliases = const {},
  final ClassType? stackContext,
}) {
  final Map<RuntimeRole, FunctionTarget> entries = .unmodifiable(entries);

  /// Trusted external declarations resolved to their ordinary runtime body.
  final Map<FunctionTarget, FunctionTarget> aliases = .unmodifiable(aliases);
  final Map<FunctionTarget, MemoryOperation> primitives = .unmodifiable(
    primitives,
  );
  final List<FunctionTarget> nonAllocating = .unmodifiable(nonAllocating);
  final Map<FunctionTarget, SystemLibrary> systemFunctions = .unmodifiable(
    systemFunctions,
  );

  /// Reads trusted annotations while their owning analysis session is open.
  factory resolve(
    CheckedLibraries input,
    Iterable<ResolvedLibraryResult> libraries,
    FunctionTarget? Function(ExecutableElement) targetFor,
    ClassType Function(InterfaceElement, ResolvedUnitResult, ast.AstNode)
    classFor,
  ) {
    final visitor = _RuntimeDeclarations(input, libraries, targetFor, classFor);
    final aliases = <FunctionTarget, FunctionTarget>{};
    for (final MapEntry(key: source, value: role) in visitor.aliases.entries) {
      final target = visitor.entries[role];
      if (target == null ||
          source.kind != .function ||
          target.kind != .function ||
          source.typeParameters.isNotEmpty ||
          target.typeParameters.isNotEmpty ||
          source.signature != target.signature) {
        throw ArgumentError('Incompatible runtime entry declaration: $role');
      }
      aliases[source] = target;
    }
    return .new(
      visitor.entries,
      visitor.primitives,
      visitor.nonAllocating,
      visitor.systemFunctions,
      aliases: aliases,
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
  final aliases = <FunctionTarget, RuntimeRole>{};
  final primitives = <FunctionTarget, MemoryOperation>{};
  final nonAllocating = <FunctionTarget>[];
  final systemFunctions = <FunctionTarget, SystemLibrary>{};
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
    if (noAllocation) {
      nonAllocating.add(target);
      return;
    }
    final values = isEntry
        ? RuntimeRole.values
        : isPrimitive
        ? MemoryOperation.values
        : SystemLibrary.values;
    var enumeration = value!.getField(
      isEntry
          ? 'role'
          : isPrimitive
          ? 'operation'
          : 'library',
    );
    int? index;
    while (enumeration != null && index == null) {
      index = enumeration.getField('index')?.toIntValue();
      enumeration = enumeration.getField('(super)');
    }
    if (index == null || index < 0 || index >= values.length) {
      throw ArgumentError('Invalid runtime annotation.');
    }
    if (system) {
      if (!element.isExternal || systemFunctions.containsKey(target)) {
        throw ArgumentError('Invalid system declaration: ${target.name}');
      }
      systemFunctions[target] = SystemLibrary.values[index];
    } else if (isEntry) {
      final role = RuntimeRole.values[index];
      if (element.isExternal) {
        if (aliases.containsKey(target)) {
          throw ArgumentError('Repeated runtime declaration: ${target.name}');
        }
        aliases[target] = role;
      } else {
        if (entries.containsKey(role)) {
          throw ArgumentError('Repeated runtime entry: $role');
        }
        entries[role] = target;
      }
    } else {
      if (!element.isExternal || primitives.containsKey(target)) {
        throw ArgumentError('Invalid primitive declaration: ${target.name}');
      }
      primitives[target] = MemoryOperation.values[index];
    }
  }
}
