import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';
import 'package:dartc/runtime/contracts.dart';

import 'analysis/session.dart';

/// Resolves trusted runtime annotations against checked declaration identities.
final class RuntimeDeclarations(
  final IrProgram program,
  final CheckedLibraries input,
  final Uri contracts,
) extends RecursiveAstVisitor<void> {
  this {
    for (final library in input.libraries) {
      if (!library.element.uri.toString().startsWith(
        contracts.resolve('.').toString(),
      )) {
        continue;
      }
      for (final source in library.units) {
        unit = source;
        source.unit.accept(this);
      }
    }
  }

  final entries = <RuntimeRole, FunctionTarget>{};
  final primitives = <FunctionTarget, MemoryOperation>{};
  final nonAllocating = <FunctionTarget>[];
  final weakFields = <InstanceField>{};
  final ephemerons = <InstanceField, String>{};
  late ResolvedUnitResult unit;

  @override
  void visitFieldDeclaration(ast.FieldDeclaration node) {
    for (final annotation in node.metadata) {
      final value = input.annotationValue(unit, annotation);
      final type = value?.type;
      if (type is! dart.InterfaceType ||
          type.element.library.uri != contracts) {
        continue;
      }
      final weak = type.element == type.element.library.getClass('WeakSlot');
      final conditional =
          type.element == type.element.library.getClass('EphemeronKey');
      if (!weak && !conditional) continue;
      for (final variable in node.fields.variables) {
        final element = variable.declaredFragment!.element as FieldElement;
        final owner = element.enclosingElement as InterfaceElement;
        final declaration = program.classes.singleWhere(
          (c) =>
              c.type.library == owner.library.uri && c.type.name == owner.name,
        );
        final field = declaration.fields.singleWhere(
          (f) => f.name == element.name,
        );
        if (weak) {
          weakFields.add(field);
        } else {
          final name = value!.getField('valueField')?.toStringValue();
          if (name == null) {
            throw ArgumentError('Invalid ephemeron value field.');
          }
          ephemerons[field] = name;
        }
      }
    }
  }

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
        when element.library.uri != contracts) {
      return;
    }
    final type = value?.type;
    if (type is! dart.InterfaceType) return;
    final source = type.element.library;
    final isEntry = type.element == source.getClass('RuntimeEntry');
    final isPrimitive = type.element == source.getClass('Primitive');
    final noAllocation = type.element == source.getClass('NonAllocating');
    if (!isEntry && !isPrimitive && !noAllocation) return;
    final owner = element.enclosingElement;
    final kind = switch (element) {
      GetterElement(isStatic: false) => FunctionKind.getter,
      GetterElement() => FunctionKind.staticGetter,
      SetterElement(isStatic: false) => FunctionKind.setter,
      SetterElement() => FunctionKind.staticSetter,
      MethodElement(isStatic: false) => FunctionKind.method,
      _ => FunctionKind.function,
    };
    final target = [...program.functions, ...program.externals]
        .singleWhere(
          (body) =>
              body.target.library == element.library.uri &&
              body.target.name == element.name &&
              body.target.kind == kind &&
              body.target.owner?.name ==
                  (owner is InterfaceElement ? owner.name : null),
        )
        .target;
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
