import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

/// Introduces ordinary IR bridges before semantic analysis of native boundaries.
///
/// [imports] supplies signatures without resolving external symbols. [roots]
/// are independent Dart entries; exports instead enter through their ABI bridge.
final class NativeBoundaries(
  IrProgram source, {
  Map<FunctionTarget, NativeSignature> imports = const {},
  Map<FunctionTarget, NativeExport> exports = const {},
  Iterable<FunctionTarget> roots = const [],
}) {
  /// The source graph including native conversion and callback bodies.
  late final IrProgram program;

  /// Independent entries after native argument conversion has been introduced.
  late final Set<FunctionTarget> roots;

  /// Native callees and their original declaration and platform signature.
  late final Map<
    FunctionTarget,
    ({FunctionTarget source, NativeSignature signature})
  >
  imports;

  /// Public native symbols attached to their actual entry bodies.
  late final Map<FunctionTarget, NativeExport> exports;

  /// Address providers and ABI entries for checked callback declarations.
  late final Map<
    NativeCallbackTarget,
    ({FunctionTarget address, FunctionTarget target})
  >
  callbacks;
  final _functions = <IrFunction>[];

  this {
    final entries = roots.toSet();
    final sourceEntries = {...entries, ...exports.keys};
    if (sourceEntries.isEmpty || exports.keys.any(imports.containsKey)) {
      throw ArgumentError(
        'Expected roots and distinct native imports and exports.',
      );
    }
    for (final entry in sourceEntries) {
      if (source.implementationOf(entry) == null) {
        throw ArgumentError('Missing entry definition: ${entry.name}');
      }
    }
    final nativeImports =
        <
          FunctionTarget,
          ({FunctionTarget source, NativeSignature signature})
        >{};
    final nativeExports = <FunctionTarget, NativeExport>{};
    final nativeCallbacks =
        <
          NativeCallbackTarget,
          ({FunctionTarget address, FunctionTarget target})
        >{};
    final externals = source.externals.toList();
    for (final MapEntry(key: target, value: binding) in imports.entries) {
      final declaration = source.implementationOf(target);
      if (declaration is! IrExternal ||
          target.kind.hasReceiver ||
          !FfiTypes.canCall(binding, target.signature)) {
        throw ArgumentError(
          'Native import requires a matching external declaration: ${target.name}',
        );
      }
      if (_needsBridge(binding)) {
        final raw = _bridge(target, intoDart: false);
        externals.removeWhere((declaration) => declaration.target == target);
        externals.add(
          IrExternal(
            raw,
            effects: declaration.effects,
            terminates: declaration.terminates,
            memory: declaration.memory,
            capturesArguments: declaration.capturesArguments,
          ),
        );
        nativeImports[raw] = (source: target, signature: binding);
      } else {
        nativeImports[target] = (source: target, signature: binding);
      }
    }
    for (final MapEntry(key: target, value: binding) in exports.entries) {
      final signature = binding.signature;
      if (!FfiTypes.canExport(signature, target.signature)) {
        throw ArgumentError('Native signature mismatch: ${target.name}');
      }
      nativeExports[_needsBridge(signature)
              ? _bridge(target, intoDart: true)
              : target] =
          binding;
    }
    // Programs without callback entries need no callback reachability analysis.
    late final selected = reachableDefinitions(source, sourceEntries);
    for (final body in source.functions) {
      for (final block in body.blocks) {
        for (final instruction
            in block.instructions.whereType<NativeCallbackAddress>()) {
          if (!selected.contains(body.target)) break;
          final definition = instruction.target;
          if (nativeCallbacks.containsKey(definition)) continue;
          final signature = definition.dartSignature;
          final target = FunctionTarget(
            null,
            'callback${nativeCallbacks.length}',
            signature.result,
            [
              if (definition is ClosureCallbackTarget) ValueType.integer,
              ...signature.parameters,
            ],
          );
          final entry = Block(target.parameterTypes);
          final result = entry.emit(switch (definition) {
            StaticCallbackTarget(:final function) => DirectCall(
              function,
              function.signature.bind(
                entry.parameters,
                {},
                (i) => source.implementationOf(function)!.defaults[i]!,
              ),
            ),
            ClosureCallbackTarget(:final lookup) => FunctionCall(
              entry.emit(
                UncheckedCast(
                  entry.emit(DirectCall(lookup, [entry.parameters.first])),
                  definition.dartSignature,
                ),
              ),
              entry.parameters.skip(1),
            ),
          });
          entry.finish(
            result.type == .never
                ? Unreachable(result)
                : Return(signature.result == .voidType ? null : result),
          );
          _functions.add(IrFunction(target, [entry]));
          final address = FunctionTarget(
            null,
            'callbackAddress${nativeCallbacks.length}',
            .integer,
            [],
          );
          externals.add(IrExternal(address));
          nativeCallbacks[definition] = (
            address: address,
            target: _needsBridge(definition.signature)
                ? _bridge(target, intoDart: true)
                : target,
          );
        }
      }
    }
    this.roots = .unmodifiable({...entries, ...nativeExports.keys});
    this.imports = .unmodifiable(nativeImports);
    this.exports = .unmodifiable(nativeExports);
    callbacks = .unmodifiable(nativeCallbacks);
    program = _functions.isEmpty
        ? source
        : IrProgram(
            source.classes,
            [...source.functions, ..._functions],
            globals: source.globals,
            externals: externals,
          );
  }

  bool _needsBridge(NativeSignature signature) =>
      (signature.result is NativePointerType ||
          signature.result is NativeCompoundType) ||
      signature.parameters.any(
        (type) => type is NativePointerType || type is NativeCompoundType,
      );

  FunctionTarget _bridge(FunctionTarget dart, {required bool intoDart}) {
    bool compound(ValueType type) =>
        type is ClassType && type.nativeType is NativeCompoundType;
    ValueType rawType(ValueType type) =>
        FfiTypes.isPointer(type) || compound(type) ? .integer : type;
    final resultCompound = compound(dart.returnType);
    final raw = FunctionTarget(
      null,
      'native${_functions.length}',
      resultCompound ? .voidType : rawType(dart.returnType),
      [
        if (resultCompound) ValueType.integer,
        ...dart.parameterTypes.map(rawType),
      ],
    );
    final (source, destination) = intoDart ? (raw, dart) : (dart, raw);
    final entry = Block(source.parameterTypes);
    final offset = intoDart && resultCompound ? 1 : 0;
    final resultStorage = !intoDart && resultCompound
        ? entry.emit(NativeView(dart.returnType as ClassType))
        : null;
    final arguments = <Value>[
      if (resultStorage != null) entry.emit(NativeAddress(resultStorage)),
    ];
    for (final (i, type) in dart.parameterTypes.indexed) {
      final value = entry.parameters[i + offset];
      arguments.add(
        FfiTypes.isPointer(type)
            ? entry.emit(
                intoDart
                    ? PointerFromAddress(value, type as ClassType)
                    : PointerAddress(value),
              )
            : compound(type)
            ? entry.emit(
                intoDart
                    ? NativeView(type as ClassType, address: value, copy: true)
                    : NativeAddress(value),
              )
            : value,
      );
    }
    Value result = entry.emit(DirectCall(destination, arguments));
    if (!intoDart) {
      for (final value in entry.parameters) {
        entry.emit(KeepAlive(value));
      }
    }
    if (resultCompound) {
      if (intoDart) {
        entry.emit(
          CopyNative(
            entry.parameters.first,
            entry.emit(NativeAddress(result)),
            (dart.returnType as ClassType).nativeType!,
          ),
        );
        entry.emit(KeepAlive(result));
        entry.finish(const Return());
      } else {
        entry.finish(Return(resultStorage!));
      }
    } else {
      if (FfiTypes.isPointer(dart.returnType)) {
        result = entry.emit(
          intoDart
              ? PointerAddress(result)
              : PointerFromAddress(result, dart.returnType as ClassType),
        );
      }
      entry.finish(Return(result));
    }
    _functions.add(IrFunction(source, [entry]));
    return raw;
  }
}
