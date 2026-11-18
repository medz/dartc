import 'package:dartc/interop.dart';

import 'function.dart';
import 'ffi_types.dart';
import 'native_data.dart';
import 'program.dart';
import 'signature.dart';
import 'type.dart';
import 'value.dart';

/// The actual entry implementing one source export's native signature.
typedef NativeExportEntry = ({FunctionTarget entry, NativeSignature signature});

/// A terminal native import and the source declaration it implements.
typedef NativeImportEntry = ({
  FunctionTarget source,
  NativeSignature signature,
  bool isLeaf,
  bool isNonAllocating,
});

/// Native entry identities and module ownership carried by a rewritten graph.
///
/// These bindings describe existing ordinary IR, not additional execution
/// roots. Rewriters preserve them together with the referenced declarations.
/// Output symbol names remain a caller's separate linking configuration.
final class NativeBoundaryBindings({
  Map<FunctionTarget, NativeExportEntry> exports = const {},
  Map<FunctionTarget, NativeImportEntry> imports = const {},
  Map<NativeCallbackTarget, ({FunctionTarget address, FunctionTarget target})>
      callbacks =
      const {},
  Map<FunctionTarget, FunctionTarget> processes = const {},
  final NativeData? context,
  final FunctionTarget? contextQuery,
  final FunctionTarget? failure,
  final FunctionTarget? cleanup,
  final bool persistent = false,
}) {
  final Map<FunctionTarget, NativeExportEntry> exports = .unmodifiable(exports);
  final Map<FunctionTarget, NativeImportEntry> imports = .unmodifiable(imports);
  final Map<
    NativeCallbackTarget,
    ({FunctionTarget address, FunctionTarget target})
  >
  callbacks = .unmodifiable(callbacks);
  final Map<FunctionTarget, FunctionTarget> processes = .unmodifiable(
    processes,
  );

  this {
    if (context == null &&
        (contextQuery != null ||
            failure != null ||
            cleanup != null ||
            persistent ||
            processes.isNotEmpty)) {
      throw ArgumentError('Native lifecycle bindings require their context.');
    }
    if (context != null && failure == null) {
      throw ArgumentError(
        'Native lifecycle bindings require their failure entry.',
      );
    }
    if (context?.contextOwner case final owner?) {
      if (owner.query != contextQuery || owner.failure != failure) {
        throw ArgumentError(
          'Native context ownership differs from its bindings.',
        );
      }
    }
  }

  /// Checks that this graph supplies the declared bodies and terminal leaves.
  void checkProgram(IrProgram program) {
    void body(FunctionTarget target) {
      if (program.implementationOf(target) is! IrFunction) {
        throw ArgumentError('Missing native boundary body: ${target.name}');
      }
    }

    FunctionType raw(NativeSignature signature, {bool closure = false}) =>
        FunctionType(
          signature.result is NativeCompoundType
              ? .voidType
              : FfiTypes.rawValueType(signature.result),
          [
            if (signature.result is NativeCompoundType) ValueType.integer,
            if (closure) ValueType.integer,
            ...signature.parameters.map(FfiTypes.rawValueType),
          ],
        );

    void entry(FunctionTarget target, FunctionType signature) {
      if (target.kind != .function || target.signature != signature) {
        throw ArgumentError(
          'Invalid native boundary signature: ${target.name}',
        );
      }
    }

    for (final binding in exports.entries) {
      body(binding.key);
      body(binding.value.entry);
      if (!FfiTypes.canExport(binding.value.signature, binding.key.signature)) {
        throw ArgumentError('Invalid native export source signature.');
      }
      entry(binding.value.entry, raw(binding.value.signature));
    }
    final importSources = <FunctionTarget>{};
    for (final binding in imports.entries) {
      if (program.implementationOf(binding.key) is! IrExternal ||
          program.implementationOf(binding.value.source) == null ||
          !importSources.add(binding.value.source) ||
          !FfiTypes.canCall(
            binding.value.signature,
            binding.value.source.signature,
          )) {
        throw ArgumentError('Missing native import binding.');
      }
      final external = program.implementationOf(binding.key) as IrExternal;
      final info = binding.value;
      if ((info.isLeaf || info.isNonAllocating) &&
              external.effects.contains(Effect.callsUserCode) ||
          info.isNonAllocating &&
              (external.effects.contains(Effect.allocates) ||
                  external.effects.contains(Effect.mayThrow))) {
        throw ArgumentError(
          'Native effects differ from their checked binding.',
        );
      }
      if (info.signature.result case final NativeCompoundType type) {
        final memory = external.memory;
        if (memory is! NativeResultMemory || memory.type != type) {
          throw ArgumentError(
            'Native aggregate result lacks its actual output region.',
          );
        }
      } else if (external.memory is NativeResultMemory) {
        throw ArgumentError(
          'A scalar native entry cannot have aggregate result storage.',
        );
      }
      entry(binding.key, raw(binding.value.signature));
    }
    for (final binding in callbacks.entries) {
      final source = switch (binding.key) {
        StaticCallbackTarget(:final function) => function,
        ClosureCallbackTarget(:final lookup) => lookup,
      };
      if (program.implementationOf(source) == null) {
        throw ArgumentError('Missing native callback source.');
      }
      body(binding.value.target);
      entry(
        binding.value.target,
        raw(
          binding.key.signature,
          closure: binding.key is ClosureCallbackTarget,
        ),
      );
      entry(binding.value.address, FunctionType(.integer, []));
      if (program.implementationOf(binding.value.address) is! IrExternal) {
        throw ArgumentError('Missing native callback address entry.');
      }
    }
    for (final binding in processes.entries) {
      body(binding.key);
      body(binding.value);
      entry(binding.value, FunctionType(.integer, binding.key.parameterTypes));
    }
    if (cleanup case final target?) {
      body(target);
      entry(target, FunctionType(.voidType, []));
    }
    if (contextQuery case final target?) {
      body(target);
      entry(target, FunctionType(.integer, []));
    }
    if (failure case final target?) {
      if (program.implementationOf(target) is! IrExternal ||
          target.kind != .function ||
          target.signature != FunctionType(.never, [])) {
        throw ArgumentError('Invalid native publication failure entry.');
      }
    }
  }
}
