import 'block.dart';
import 'core_types.dart';
import 'format.dart';
import 'signature.dart';
import 'type.dart';
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

  /// Constant instances whose complete storage is checked against supplied classes.
  Set<ObjectConstant> get objects => _references.objects;

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

  this {
    if (target.kind == .closure || target.kind == .fieldInitializer) {
      throw ArgumentError('Invalid external declaration ${target.name}.');
    }
    final parameters = switch (memory) {
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
              index >= target.parameterTypes.length ||
              target.parameterTypes[index] != ValueType.integer,
        ) ||
        memory is ZeroedMemory && target.returnType != ValueType.integer ||
        (memory is WrittenMemory || memory is ReleasedMemory) &&
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

  /// Whether this graph returns directly or uses an async/generator activation.
  final FunctionBodyKind bodyKind = .synchronous,

  /// The element type of a generator body, absent for an ordinary function.
  final ValueType? yieldType,

  /// The reified value type of an async body's Future, not its public result.
  final ValueType? completionType,
}) extends IrCallable {
  /// The reachable blocks in the supplied order, starting with [entry].
  final List<Block> blocks = .unmodifiable(blocks);

  /// Source positions and logical frames of instructions and terminators.
  ///
  /// A [Block] key locates its terminator; omitted entries have no source origin.
  final Map<Object, SourceLocation> sourceLocations = .unmodifiable(
    sourceLocations,
  );

  /// The local bodies that this graph can instantiate.
  Set<FunctionTarget> get closures => _references.closures;

  /// The global declarations directly read or written by this graph.
  Set<GlobalVariable> get globals => _references.globals;

  /// The block whose parameters receive the function arguments.
  Block get entry => blocks.first;

  /// Whether moving this body across a call boundary changes its frame reads.
  bool get observesCallerFrame => blocks.any(
    (block) =>
        block.instructions.any(
          (operation) =>
              operation is CaptureStackTrace || operation is FrameValue,
        ) ||
        switch (block.end) {
          Invoke(operation: CaptureStackTrace() || FrameValue()) => true,
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
    );
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
