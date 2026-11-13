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
      sourceLocation: input.sourceLocation,
      runtimeContracts: input.runtimeContracts,
      runtimeSources: input.runtimeSources,
      sourceLibraries: {for (final library in input.libraries) library.element},
    );
    final libraries = [...input.libraries];
    final registered = {for (final library in libraries) library.element};
    for (var i = 0; i < libraries.length; i++) {
      final library = libraries[i];
      bindings.registerLibrary(library);
      // Mixin binding needs its superclass sources before synchronous lowering.
      for (final dependency in [
        for (final fragment in library.element.fragments)
          ...fragment.importedLibraries,
        ...library.element.exportedLibraries,
      ]) {
        if ((dependency.isInSdk ||
                input.runtimeSources.contains(dependency.uri)) &&
            registered.add(dependency)) {
          libraries.add(await input.resolveLibrary(dependency));
        }
      }
    }
    final native = NativeBindings(bindings);
    for (final library in libraries) {
      if (input.libraries.contains(library) ||
          input.runtimeSources.contains(library.element.uri)) {
        native.bind(library);
      }
    }
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

    var dependencyClass = 0, dependencyFunction = 0, mixin = 0;
    while (dependencyClass < bindings.dependencyClasses.length ||
        dependencyFunction < bindings.dependencyFunctions.length ||
        mixin < bindings.mixinDeclarations.length) {
      if (dependencyClass < bindings.dependencyClasses.length) {
        final element = bindings.dependencyClasses[dependencyClass++];
        final (unit, node) =
            bindings.sourceOf(element) ??
            (throw UnsupportedError(
              'Class source unavailable: ${element.name}',
            ));
        final declaration = lowerClass(unit, bindings, node, functions);
        bindings.bindInheritedPrimitiveMembers(element, unit, node);
        // Primitive declarations and their SDK implementations share a class.
        if (!{
          ValueType.number,
          ValueType.integer,
          ValueType.floating,
          ValueType.string,
        }.contains(declaration.type)) {
          classes.add(declaration);
        }
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
      final element = bindings.dependencyFunctions[dependencyFunction++];
      final bound = bindings.boundTarget(element);
      if (bound != null &&
          functions.any((function) => function.target == bound)) {
        continue;
      }
      final library = await input.resolveLibrary(element.library);
      bindings.registerLibrary(library);
      final declaration = library.getFragmentDeclaration(
        element is PropertyAccessorElement && element.isOriginVariable
            ? element.variable.firstFragment
            : element.fragments.last,
      );
      if (declaration == null) {
        throw UnsupportedError(
          'Declaration source unavailable: ${element.name}',
        );
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
          'Function source unavailable: ${element.name}',
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

    final intrinsics = [...bindings.lowerIntrinsics(), ...native.accessors];
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
      runtime: RuntimeDeclarations.resolve(
        input,
        bindings.libraries,
        bindings.boundTarget,
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
  RuntimeDeclarations runtime,
});
