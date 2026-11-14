import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

/// Resolves semantic operations to their checked implementation before analysis.
///
/// Generated support bodies use the same normalization as source bodies.
/// Physical storage, calling conventions and machine operands are chosen later.
final class ProgramNormalization(final IrProgram program) {
  final _classes = {
    for (final declaration in program.classes) declaration.type: declaration,
  };

  /// Returns the original program when no operation needs lowering.
  IrProgram run() {
    var changed = false;
    final functions = <IrFunction>[];
    for (final source in program.functions) {
      final result = function(source);
      changed |= !identical(result, source);
      functions.add(result);
    }
    return changed
        ? IrProgram(
            program.classes,
            functions,
            globals: program.globals,
            externals: program.externals,
          )
        : program;
  }

  /// Lowers a source or generated body without changing its declaration identity.
  IrFunction function(IrFunction source) {
    final operations = <Instruction, Instruction>{};
    for (final block in source.blocks) {
      for (final operation in [
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ]) {
        final replacement = switch (operation) {
          NewCollection(:final collectionType, :final growable) => _construct(
            collectionType,
            collectionType.declaration == CoreTypes.list ? 'empty' : 'new',
            const [],
            collectionType.declaration == CoreTypes.list
                ? {'growable': growable ?? const Constant.boolean(true)}
                : const {},
          ),
          ListFilled(
            :final type,
            :final length,
            :final fill,
            :final growable,
          ) =>
            _construct(
              type as ClassType,
              'filled',
              [length, fill],
              {'growable': growable},
            ),
          ListFrom(:final type, :final elements, :final growable) => _construct(
            type as ClassType,
            'from',
            [elements],
            {'growable': growable},
          ),
          CollectionSpread(
            isMethodCall: false,
            :final collection,
            :final source,
          )
              when CoreTypes.view(collection.type, CoreTypes.list) != null =>
            DirectCall(
              program.classes
                  .singleWhere((c) => c.listStorage != null)
                  .listStorage!
                  .spread,
              [collection, source],
              typeArguments: [
                CoreTypes.view(
                  collection.type,
                  CoreTypes.list,
                )!.typeArguments.single,
              ],
            ),
          _ => null,
        };
        if (replacement != null) operations[operation] = replacement;
      }
    }
    return operations.isEmpty
        ? source
        : FunctionRewrite(source, operations: operations).run();
  }

  Instruction _construct(
    ClassType type,
    String name,
    List<Value> positional,
    Map<String, Value> named,
  ) {
    final constructor =
        _classes[type.declaration]?.constructors[name] ??
        (throw ArgumentError(
          'Missing checked collection constructor: ${type.dartName}.$name',
        ));
    final (:target, :ownerType) = constructor.resolveConstruction(type);
    final body =
        program.implementationOf(target) ??
        (throw ArgumentError('Missing constructor body: ${target.name}'));
    final arguments = target.signature.bind<Value>(
      positional,
      named,
      (index) => body.defaults[index]!,
    );
    return target.kind == .initializer
        ? Construct(target, arguments, instantiatedType: ownerType)
        : DirectCall(target, arguments, ownerType: ownerType);
  }
}
