import 'package:dartc/interop.dart' show NativeCompoundType;

import 'block.dart';
import 'cell_storage.dart';
import 'core_types.dart';
import 'format.dart';
import 'execution_shape.dart';
import 'module_object.dart';
import 'origin.dart';
import 'signature.dart';
import 'type.dart';
import 'type_binding.dart';
import 'value.dart';
import 'verify.dart';

/// A callable supplied by the program, with a Dart signature and checked defaults.
///
/// Verification seals all referenced type metadata against later initialization.
sealed class IrCallable(
  /// The declaration used by calls and tear-offs.
  final FunctionTarget target, {
  Map<int, Constant> defaults = const {},
}) {
  /// Constant defaults keyed by explicit parameter slot, excluding the receiver.
  final Map<int, Constant> defaults = .unmodifiable(defaults);
  late final FunctionReferences _references;

  /// Direct call and tear-off targets, including those in defaults.
  Set<FunctionTarget> get callees => _references.callees;

  /// Virtual declarations paired with the receiver type at each use.
  Set<({ValueType receiver, FunctionTarget target})> get virtualMembers =>
      _references.virtualMembers;

  /// Methods extracted as function values, retaining direct `super` selection.
  Set<({ValueType receiver, FunctionTarget method, bool direct})>
  get methodTearOffs => _references.methodTearOffs;

  /// Implicit virtual calls, including their possible receiver types.
  Set<({ValueType receiver, MemberSelector selector})> get implicitMembers =>
      _references.implicitMembers;

  /// Classes instantiated by this body, constructor tear-offs or its constants.
  Set<ClassType> get instantiatedClasses => _references.instantiatedClasses;

  /// Instance slots referenced by instructions or embedded constants.
  Set<InstanceField> get fields => _references.fields;

  /// Exact storage contracts used by internal cell capability views.
  Set<CellStorage> get cellStorages => _references.cellStorages;

  /// Constant instances whose complete storage is checked against supplied classes.
  Set<ObjectConstant> get objects => _references.objects;

  /// Module identities referenced by this body, with their initial bindings.
  Set<ModuleObject> get moduleObjects => _references.moduleObjects;

  /// Function tear-offs referenced by the body or nested constant defaults.
  Set<FunctionConstant> get functionConstants => _references.functionConstants;

  /// Constant Lists and Sets, including nested elements and defaults.
  Set<SequenceConstant> get sequenceConstants => _references.sequenceConstants;

  /// Record shapes constructed here, including nested constants and defaults.
  Set<RecordType> get recordTypes => _references.recordTypes;

  /// Nominal identities used by the signature, constants and graph.
  Set<ClassType> get referencedClasses => _references.classes;

  /// Deferred prefixes loaded or checked by this body.
  Set<DeferredImport> get deferredImports => _references.deferredImports;

  this {
    final optional = target.signature.optionalSlots;
    if (target.isAbstract ||
        target.redirect != null ||
        optional.length != this.defaults.length ||
        optional.any(
          (slot) =>
              !this.defaults.containsKey(slot) ||
              !target.signature.parameters[slot].accepts(
                this.defaults[slot]!.type,
              ),
        )) {
      throw ArgumentError(
        'Invalid implementation or defaults for ${target.name}.',
      );
    }
  }
}

/// Native storage touched by an external call, independently of its other effects.
sealed class const ExternalMemory() {
  const factory arbitrary() = ArbitraryMemory;
  const factory unchanged() = UnchangedMemory;
  const factory zeroed(int lengthParameter) = ZeroedMemory;
  const factory write(int addressParameter, int lengthParameter) =
      WrittenMemory;
  const factory release(int addressParameter, int lengthParameter) =
      ReleasedMemory;
}

/// May modify storage reachable through arguments or previously escaped values.
final class const ArbitraryMemory() extends ExternalMemory;

/// Leaves existing storage and its lifetime unchanged.
final class const UnchangedMemory() extends ExternalMemory;

/// Returns a fresh zero-filled mapping, or zero on failure; never a GC reference.
final class const ZeroedMemory(final int lengthParameter)
    extends ExternalMemory;

/// May overwrite only the supplied address range; follows no stored pointers.
final class const WrittenMemory(
  final int addressParameter,
  final int lengthParameter,
) extends ExternalMemory;

/// Ends the lifetime of the supplied address range; follows no stored pointers.
final class const ReleasedMemory(
  final int addressParameter,
  final int lengthParameter,
) extends ExternalMemory;

/// The C adapter writes a by-value result into its first raw argument.
/// Result storage is ABI-owned and never becomes a source argument.
/// [arguments] keeps indices in the original source signature.
final class NativeResultMemory(
  final NativeCompoundType type,
  final ExternalMemory arguments,
) extends ExternalMemory;

/// A Dart callable whose implementation is supplied outside the IR graph.
///
/// Calls retain normal Dart argument and return types. A native binding must
/// separately specify the platform ABI and any necessary conversions.
final class IrExternal(
  super.target, {
  super.defaults,
  Iterable<Effect> effects = Effect.values,

  /// Whether every invocation finishes, rather than diverging or suspending forever.
  /// This trusted promise is independent of effects and does not exclude throws.
  final bool terminates = false,

  /// Native storage access; output and other observable effects remain in [effects].
  final ExternalMemory memory = const .arbitrary(),

  /// Whether argument capabilities can remain accessible after this call returns.
  final bool capturesArguments = true,
}) extends IrCallable {
  /// Effects promised by the external implementation, conservative by default.
  ///
  /// This is a trusted contract, not a conclusion derived from the signature.
  /// It does not promise termination or make unknown results constant.
  final Set<Effect> effects = .unmodifiable(effects);

  /// Applies a native implementation's promises without discarding independent
  /// memory, escape, failure or termination facts. Leaf calls cannot reenter;
  /// only an explicit non-allocating contract also excludes allocation and throws.
  IrExternal bindNative(
    FunctionTarget entry, {
    required bool isLeaf,
    required bool isNonAllocating,
    NativeCompoundType? resultStorage,
  }) {
    if (entry == target &&
        !isLeaf &&
        !isNonAllocating &&
        resultStorage == null) {
      return this;
    }
    return IrExternal(
      entry,
      defaults: entry == target ? defaults : const {},
      effects: {
        ...effects.difference({
          if (isLeaf || isNonAllocating) Effect.callsUserCode,
          if (isNonAllocating) ...[Effect.allocates, Effect.mayThrow],
        }),
        if (resultStorage != null) Effect.writesStorage,
      },
      memory: resultStorage == null
          ? memory
          : NativeResultMemory(
              resultStorage,
              effects.contains(Effect.writesStorage)
                  ? memory
                  : const ExternalMemory.unchanged(),
            ),
      capturesArguments: capturesArguments,
      terminates: terminates,
    );
  }

  this {
    if (target.kind == .closure || target.kind == .fieldInitializer) {
      throw ArgumentError('Invalid external declaration ${target.name}.');
    }
    final hiddenResult = memory is NativeResultMemory;
    final offset = hiddenResult ? 1 : 0;
    final access = hiddenResult
        ? (memory as NativeResultMemory).arguments
        : memory;
    final parameters = switch (access) {
      ZeroedMemory(:final lengthParameter) => [lengthParameter],
      WrittenMemory(:final addressParameter, :final lengthParameter) ||
      ReleasedMemory(
        :final addressParameter,
        :final lengthParameter,
      ) => [addressParameter, lengthParameter],
      _ => const <int>[],
    };
    if (parameters.any(
          (index) =>
              index < 0 ||
              index + offset >= target.parameterTypes.length ||
              target.parameterTypes[index + offset] != ValueType.integer,
        ) ||
        hiddenResult &&
            (target.parameterTypes.firstOrNull != ValueType.integer ||
                target.returnType != ValueType.voidType ||
                access is NativeResultMemory) ||
        access is ZeroedMemory && target.returnType != ValueType.integer ||
        (hiddenResult || access is WrittenMemory || access is ReleasedMemory) &&
            !this.effects.contains(Effect.writesStorage)) {
      throw ArgumentError('Invalid native storage contract.');
    }
    _references = verifyCallable(target, defaults.values);
  }
}

/// A verified SSA control-flow graph for one callable body.
///
/// Suspendable graphs explicitly represent their continuations. Semantic
/// normalization exposes their calls and state before analysis and codegen.
final class IrFunction(
  super.target,
  Iterable<Block> blocks, {
  super.defaults,
  Map<Object, SourceLocation> sourceLocations = const {},
  Map<Object, IrOrigin> origins = const {},
  Iterable<TypeBinding> typeBindings = const [],

  /// Persistent physical choices for SSA values in this exact body.
  final FunctionExecution? execution,

  /// Whether this graph returns directly or uses an async/generator activation.
  final FunctionBodyKind bodyKind = .synchronous,

  /// The element type of a generator body, absent for an ordinary function.
  final ValueType? yieldType,

  /// The reified value type of an async body's Future, not its public result.
  final ValueType? completionType,
}) extends IrCallable {
  /// The reachable blocks in the supplied order, starting with [entry].
  final List<Block> blocks = .unmodifiable(blocks);

  /// Checked body-only reification; these binders never enter the public ABI.
  final List<TypeBinding> typeBindings = .unmodifiable(typeBindings);

  /// Source positions and logical frames of instructions and terminators.
  ///
  /// A [Block] key locates its terminator; omitted entries have no source origin.
  final Map<Object, SourceLocation> sourceLocations = .unmodifiable(
    sourceLocations,
  );

  /// Semantic identities retained across rewrites and contextual copies.
  /// These are not Dart stack frames or source coordinates.
  final Map<Object, IrOrigin> origins = .unmodifiable(origins);

  /// The original semantic site and its inline/clone path.
  IrOrigin originOf(Object site) => origins[site] ?? IrOrigin(target, site);

  /// All site identities, including implicit identities in an original body.
  /// Preserve these when the same graph is installed under a new entry target.
  Map<Object, IrOrigin> get originBindings => Map.unmodifiable({
    for (final block in blocks)
      for (final site in <Object>[
        block,
        ...block.parameters,
        ...block.instructions,
        ...block.successors,
        if (block.end case Invoke(:final operation)) operation,
      ])
        site: originOf(site),
  });

  /// The local bodies that this graph can instantiate.
  Set<FunctionTarget> get closures => _references.closures;

  /// The global declarations directly read or written by this graph.
  Set<GlobalVariable> get globals => _references.globals;

  /// The block whose parameters receive the function arguments.
  Block get entry => blocks.first;

  /// Descriptor dependencies implicit in the types used by an operation.
  Iterable<Value> typeInputsOf(Instruction operation) sync* {
    for (final binding in typeBindings) {
      if (!identical(binding.value, operation) &&
          operation.referencedTypes.any(
            (type) => type.freeTypeParameters.contains(binding.parameter),
          )) {
        yield binding.value;
      }
    }
  }

  /// Whether moving this body changes frame reads, storage or binding lifetime.
  bool get observesCallerFrame => blocks.any(
    (block) =>
        block.instructions.any(
          (operation) =>
              operation is CaptureStackTrace ||
              operation is FrameValue ||
              operation is NativeLocalStorage ||
              operation is BindNativeContext,
        ) ||
        switch (block.end) {
          Invoke(
            operation: CaptureStackTrace() ||
                FrameValue() ||
                NativeLocalStorage() ||
                BindNativeContext(),
          ) =>
            true,
          _ => false,
        },
  );

  /// Verifies the graph rooted at the first of [blocks].
  ///
  /// Throws [ArgumentError] when the entry parameters differ from the signature.
  /// Throws [StateError] for an empty or malformed graph. Every block must be
  /// sealed and reachable, and each SSA definition must dominate its uses.
  /// Source origins require a graph-owned instruction or block; foreign keys
  /// throw [ArgumentError]. [SourceLocation] validates any supplied coordinates.
  /// Ordinary returns must match the callable result. Generator returns complete
  /// iteration and supply only `null`; yields must match [yieldType].
  this {
    final result = switch ((bodyKind, yieldType, completionType)) {
      (.synchronous, null, null) => null,
      (.asynchronous, null, final t?) when isDartType(t) => CoreTypes.futureOf(
        t,
      ),
      (.syncGenerator, final t?, null) when isDartType(t) =>
        CoreTypes.iterableOf(t),
      (.asyncGenerator, final t?, null) when isDartType(t) =>
        CoreTypes.streamOf(t),
      _ => throw ArgumentError('Invalid body types for ${target.name}.'),
    };
    if (result != null &&
        (!target.returnType.accepts(result) ||
            yieldType != null && target.returnType == .voidType ||
            switch (target.kind) {
              .initializer ||
              .factory ||
              .fieldInitializer ||
              .setter ||
              .staticSetter => true,
              _ => false,
            })) {
      throw ArgumentError('Invalid suspendable body for ${target.name}.');
    }
    _references = verifyCallable(
      target,
      defaults.values,
      blocks: this.blocks,
      bodyKind: bodyKind,
      yieldType: yieldType,
      completionType: completionType,
      typeBindings: this.typeBindings,
    );
    execution?.checkValues(this);
    if (origins.isNotEmpty) {
      final owned = <Object>{
        for (final block in this.blocks) ...[
          block,
          ...block.parameters,
          ...block.instructions,
          ...block.successors,
          if (block.end case Invoke(:final operation)) operation,
        ],
      };
      if (origins.keys.any((site) => !owned.contains(site))) {
        throw ArgumentError('Semantic origins require owned graph sites.');
      }
    }
    if (sourceLocations.isNotEmpty) {
      final sites = <Object>{
        for (final block in this.blocks) ...[
          block,
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ],
      };
      for (final key in sourceLocations.keys) {
        if (!sites.contains(key)) {
          throw ArgumentError('Invalid source location for ${target.name}.');
        }
      }
    }
  }

  /// Writes the typed blocks, instructions and outgoing edges to [output].
  void writeTo(StringSink output) => writeFunction(
    output,
    target,
    blocks,
    bodyKind: bodyKind,
    yieldType: yieldType,
    completionType: completionType,
  );
}
