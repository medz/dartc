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

  /// Statically selected declarations whose implementation needs virtual lookup.
  Set<FunctionTarget> get virtualMembers => _references.virtualMembers;

  /// Methods extracted as function values, retaining direct `super` selection.
  Set<({FunctionTarget method, bool direct})> get methodTearOffs =>
      _references.methodTearOffs;

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

/// A Dart callable whose implementation is supplied outside the IR graph.
///
/// Calls retain normal Dart argument and return types. A native binding must
/// separately specify the platform ABI and any necessary conversions.
final class IrExternal(super.target, {super.defaults}) extends IrCallable {
  this {
    if (target.kind == .closure || target.kind == .fieldInitializer) {
      throw ArgumentError('Invalid external declaration ${target.name}.');
    }
    _references = verifyCallable(target, defaults.values);
  }
}

/// A verified SSA control-flow graph for one callable body.
///
/// Suspendable graphs explicitly represent their continuations; a backend must
/// preserve activations or lower them to state machines before ordinary codegen.
final class IrFunction(
  super.target,
  Iterable<Block> blocks, {
  super.defaults,

  /// Whether this graph returns directly or uses an async/generator activation.
  final FunctionBodyKind bodyKind = .synchronous,

  /// The element type of a generator body, absent for an ordinary function.
  final ValueType? yieldType,

  /// The reified value type of an async body's Future, not its public result.
  final ValueType? completionType,
}) extends IrCallable {
  /// The reachable blocks in the supplied order, starting with [entry].
  final List<Block> blocks = .unmodifiable(blocks);

  /// The local bodies that this graph can instantiate.
  Set<FunctionTarget> get closures => _references.closures;

  /// The global declarations directly read or written by this graph.
  Set<GlobalVariable> get globals => _references.globals;

  /// The block whose parameters receive the function arguments.
  Block get entry => blocks.first;

  /// Verifies the graph rooted at the first of [blocks].
  ///
  /// Throws [ArgumentError] when the entry parameters differ from the signature.
  /// Throws [StateError] for an empty or malformed graph. Every block must be
  /// sealed and reachable, and each SSA definition must dominate its uses.
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
