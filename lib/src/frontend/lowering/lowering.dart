import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';

import '../analysis/session.dart';

import 'bindings.dart';
import 'class_declaration.dart';
import 'extension_declaration.dart';
import 'function.dart';
import 'global_declaration.dart';
import 'native_bindings.dart';

/// The translation from resolved Dart declarations to executable IR operations.
final class Lowering({final bool enableAssertions = false}) {
  /// Returns class declarations and verified function bodies from [input].
  ///
  /// Assertions are omitted by default. Set [enableAssertions] to evaluate
  /// assertion conditions and raise assertion errors on failures.
  ///
  /// Calls to the same declaration share a target throughout the batch.
  /// Referenced SDK top-level functions, static methods and generative classes
  /// are resolved and checked in the same session, then lowered normally.
  /// SDK factory bodies remain imports. Numeric error paths also include their
  /// SDK error classes and superclasses.
  /// Keep the owning analysis session open until the returned future completes.
  /// Constants appear as operands at their uses. Throws [FormatException] for
  /// dependency static errors and [UnsupportedError] for missing translations.
  Future<LoweringResult> lower(CheckedLibraries input) async {
    final bindings = Bindings(
      enableAssertions: enableAssertions,
      constants: input.constants,
    );
    for (final unit in input.libraries.expand((library) => library.units)) {
      for (final node in unit.unit.declarations) {
        switch (node) {
          case ast.ClassDeclaration():
            bindings.registerClass(node.declaredFragment!.element, unit, node);
          case ast.EnumDeclaration():
            bindings.registerClass(node.declaredFragment!.element, unit, node);
          case ast.MixinDeclaration():
            bindings.registerClass(node.declaredFragment!.element, unit, node);
          case ast.ClassTypeAlias():
            bindings.registerClass(node.declaredFragment!.element, unit, node);
          default:
            break;
        }
      }
    }
    final native = NativeBindings(bindings);
    input.libraries.forEach(native.bind);
    final functions = <IrCallable>[];
    final classes = <IrClass>[];
    for (final unit in input.libraries.expand((library) => library.units)) {
      for (final node in unit.unit.declarations) {
        switch (node) {
          case ast.ClassDeclaration() ||
              ast.EnumDeclaration() ||
              ast.MixinDeclaration() ||
              ast.ClassTypeAlias():
            classes.add(lowerClass(unit, bindings, node, functions));
          case ast.TypeAlias():
            break;
          case ast.ExtensionDeclaration():
            lowerExtension(unit, bindings, node.body.members, functions);
          case ast.ExtensionTypeDeclaration():
            lowerExtensionType(unit, bindings, node, functions);
          case ast.FunctionDeclaration(
            declaredFragment: final fragment?,
            :final functionExpression,
          ):
            FunctionLowering.append(
              functions,
              unit,
              bindings,
              fragment.element,
              node,
              functionExpression.body,
            );
          case ast.TopLevelVariableDeclaration(variables: final declarations):
            for (final variable in declarations.variables) {
              lowerGlobal(unit, bindings, variable, functions);
            }
          default:
            unsupported(unit, node, 'declaration');
        }
      }
    }

    for (final (application, unit, source) in bindings.mixinDeclarations) {
      bindings.replaceMixinApplication(
        lowerClass(unit, bindings, source, functions, application: application),
      );
    }
    var sdkClass = 0, sdkFunction = 0;
    while (sdkClass < bindings.sdkClasses.length ||
        sdkFunction < bindings.sdkFunctions.length) {
      if (sdkClass < bindings.sdkClasses.length) {
        final element = bindings.sdkClasses[sdkClass++];
        final library = await input.resolveLibrary(element.library);
        final declaration = library.getFragmentDeclaration(
          element.firstFragment,
        );
        if (declaration == null) {
          throw UnsupportedError('SDK class unavailable: ${element.name}');
        }
        final unit = declaration.resolvedUnit!, node = declaration.node;
        bindings.registerClass(element, unit, node);
        classes.add(lowerClass(unit, bindings, node, functions));
        continue;
      }
      final element = bindings.sdkFunctions[sdkFunction++];
      final library = await input.resolveLibrary(element.library);
      final declaration = library.getFragmentDeclaration(element.firstFragment);
      if (declaration == null) {
        throw UnsupportedError('SDK declaration unavailable: ${element.name}');
      }
      final target = bindings.target(
        element,
        declaration.resolvedUnit!,
        declaration.node,
      );
      if (functions.any((function) => function.target == target)) continue;
      final body = switch (declaration.node) {
        ast.FunctionDeclaration(:final functionExpression) =>
          functionExpression.body,
        ast.MethodDeclaration(:final body) => body,
        _ => throw UnsupportedError(
          'SDK function unavailable: ${element.name}',
        ),
      };
      FunctionLowering.append(
        functions,
        declaration.resolvedUnit!,
        bindings,
        element,
        declaration.node,
        body,
      );
    }

    final intrinsicMembers = <ClassType, List<FunctionTarget>>{};
    for (final body in bindings.intrinsics) {
      if (body.target.kind.isVirtual) {
        intrinsicMembers
            .putIfAbsent(body.target.owner!, () => [])
            .add(body.target);
      }
    }
    final program = IrProgram(
      [
        ...classes,
        ...bindings.mixinApplications,
        for (final MapEntry(key: owner, value: members)
            in intrinsicMembers.entries)
          IrClass(owner, [], members: members),
      ],
      [
        ...functions.whereType<IrFunction>(),
        ...bindings.intrinsics,
        ...bindings.mixinInitializers,
        ...bindings.libraryLoaders,
      ],
      externals: functions.whereType<IrExternal>(),
      globals: bindings.globals,
    );
    final root = input.libraries.first;
    return (
      program: program,
      entryPoint: switch (root.element.entryPoint) {
        final entry? => bindings.target(
          entry,
          root.units.first,
          root.units.first.unit,
        ),
        null => null,
      },
      exports: Map<FunctionTarget, NativeExport>.unmodifiable(native.exports),
      imports: Map<FunctionTarget, NativeReference>.unmodifiable(
        native.imports,
      ),
    );
  }
}

/// Verified Dart IR, the first library's main, and bound native declarations.
///
/// `entryPoint` identifies `main` in the first library's exported namespace,
/// or is `null` when that namespace has no entry. It retains declaration identity
/// through re-exports and remains usable after the analysis session closes.
typedef LoweringResult = ({
  IrProgram program,
  FunctionTarget? entryPoint,
  Map<FunctionTarget, NativeExport> exports,
  Map<FunctionTarget, NativeReference> imports,
});
