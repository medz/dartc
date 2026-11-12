import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';

import '../analysis/session.dart';
import '../runtime_declarations.dart';

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
  /// Referenced SDK top-level functions, static methods and classes
  /// are resolved and checked in the same session, then lowered normally.
  /// External SDK entries still require target implementations. Numeric error
  /// paths also include their SDK error classes and superclasses.
  /// Keep the owning analysis session open until the returned future completes.
  /// Constants appear as operands at their uses. Throws [FormatException] for
  /// dependency static errors and [UnsupportedError] for missing translations.
  Future<LoweringResult> lower(CheckedLibraries input) async {
    final bindings = Bindings(
      enableAssertions: enableAssertions,
      constants: input.constants,
      runtimeContracts: input.runtimeContracts,
      runtimeSources: input.runtimeSources,
    );
    for (final library in input.libraries) {
      bindings.registerLibrary(library);
    }
    Future<void> registerSdkSources(int from) async {
      for (final element in bindings.sdkClasses.skip(from)) {
        if (bindings.sourceOf(element) == null) {
          bindings.registerLibrary(await input.resolveLibrary(element.library));
        }
      }
    }

    await registerSdkSources(0);
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

    var sdkClass = 0, sdkFunction = 0, mixin = 0;
    while (sdkClass < bindings.sdkClasses.length ||
        sdkFunction < bindings.sdkFunctions.length ||
        mixin < bindings.mixinDeclarations.length) {
      if (sdkClass < bindings.sdkClasses.length) {
        await registerSdkSources(sdkClass);
        final element = bindings.sdkClasses[sdkClass++];
        final (unit, node) =
            bindings.sourceOf(element) ??
            (throw UnsupportedError('SDK class unavailable: ${element.name}'));
        classes.add(lowerClass(unit, bindings, node, functions));
        continue;
      }
      if (mixin < bindings.mixinDeclarations.length) {
        final (application, unit, source) = bindings.mixinDeclarations
            .elementAt(mixin++);
        bindings.replaceMixinApplication(
          lowerClass(
            unit,
            bindings,
            source,
            functions,
            application: application,
          ),
        );
        continue;
      }
      final element = bindings.sdkFunctions[sdkFunction++];
      final library = await input.resolveLibrary(element.library);
      final declaration = library.getFragmentDeclaration(
        element is PropertyAccessorElement && element.isOriginVariable
            ? element.variable.firstFragment
            : element.fragments.last,
      );
      if (declaration == null) {
        throw UnsupportedError('SDK declaration unavailable: ${element.name}');
      }
      final target = bindings.target(
        element,
        declaration.resolvedUnit!,
        declaration.node,
      );
      if (functions.any((function) => function.target == target)) continue;
      if (declaration.node case ast.VariableDeclaration variable) {
        lowerGlobal(declaration.resolvedUnit!, bindings, variable, functions);
        continue;
      }
      final body = switch (declaration.node) {
        ast.FunctionDeclaration(:final functionExpression) =>
          functionExpression.body,
        ast.MethodDeclaration(:final body) ||
        ast.ConstructorDeclaration(:final body) => body,
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

    final intrinsics = bindings.lowerIntrinsics();
    final intrinsicTargets = {for (final body in intrinsics) body.target};
    final intrinsicClasses = bindings.intrinsicClasses.where(
      (intrinsic) => !classes.any((source) => source.type == intrinsic.type),
    );
    final defined = {
      for (final function in [...functions, ...intrinsics]) function.target,
    };
    final program = IrProgram(
      [
        ...classes,
        if (classes.any(
              (c) => c.type.asInstanceOf(CoreTypes.enumeration) != null,
            ) &&
            !classes.any((c) => c.type == CoreTypes.enumeration))
          IrClass(CoreTypes.enumeration, [
            CoreTypes.enumIndex,
            CoreTypes.enumName,
          ]),
        ...bindings.mixinApplications,
        ...intrinsicClasses,
      ],
      [
        ...functions.whereType<IrFunction>(),
        ...intrinsics,
        ...bindings.mixinInitializers,
        ...bindings.libraryLoaders,
      ],
      externals: [
        ...functions.whereType<IrExternal>().where(
          (external) => !intrinsicTargets.contains(external.target),
        ),
        for (final declaration in intrinsicClasses)
          for (final target in [
            ...declaration.members.values,
            ...declaration.constructors.values,
          ])
            if (!target.isAbstract &&
                target.redirect == null &&
                !defined.contains(target))
              IrExternal(target, defaults: bindings.defaults(target)),
      ],
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
      runtime: RuntimeDeclarations.resolve(input, bindings.target),
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
  RuntimeDeclarations runtime,
});
