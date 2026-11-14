import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

/// Checks native bindings and preserves typed values across native boundaries.
final class NativeBindings(
  IrProgram source,
  Map<FunctionTarget, NativeImport> sourceImports,
  Map<FunctionTarget, NativeExport> sourceExports,
  Iterable<FunctionTarget> roots,
) {
  late final IrProgram program;
  final imports = <FunctionTarget, NativeImport>{};
  final exports = <FunctionTarget, NativeExport>{};
  final callbacks =
      <
        NativeCallbackEntry,
        ({FunctionTarget address, FunctionTarget target})
      >{};
  final _functions = <IrFunction>[];

  this {
    final externals = source.externals.toList();
    for (final MapEntry(key: target, value: binding) in sourceImports.entries) {
      if (source.implementationOf(target) is! IrExternal ||
          target.kind.hasReceiver ||
          !FfiTypes.canCall(binding.signature, target.signature)) {
        throw ArgumentError(
          'Native import requires a matching external declaration: ${target.name}',
        );
      }
      if (_needsBridge(binding.signature)) {
        final raw = _bridge(target, intoDart: false);
        externals.removeWhere((declaration) => declaration.target == target);
        externals.add(IrExternal(raw));
        imports[raw] = binding;
      } else {
        imports[target] = binding;
      }
    }
    for (final MapEntry(key: target, value: binding) in sourceExports.entries) {
      final signature = binding.signature;
      if (!FfiTypes.canExport(signature, target.signature)) {
        throw ArgumentError('Native signature mismatch: ${target.name}');
      }
      exports[_needsBridge(signature)
              ? _bridge(target, intoDart: true)
              : target] =
          binding;
    }
    // Programs without callback entries need no callback reachability analysis.
    late final selected = reachableDefinitions(source, roots);
    for (final body in source.functions) {
      for (final block in body.blocks) {
        for (final instruction
            in block.instructions.whereType<NativeCallbackEntry>()) {
          if (!selected.contains(body.target)) break;
          final signature = instruction.dartSignature;
          final target = FunctionTarget(
            null,
            'callback${callbacks.length}',
            signature.result,
            [
              if (instruction is NativeClosureEntryAddress) ValueType.integer,
              ...signature.parameters,
            ],
          );
          final entry = Block(target.parameterTypes);
          final result = entry.emit(switch (instruction) {
            NativeCallbackAddress(:final function) => DirectCall(
              function,
              function.signature.bind(
                entry.parameters,
                {},
                (i) => source.implementationOf(function)!.defaults[i]!,
              ),
            ),
            NativeClosureEntryAddress(:final lookup) => FunctionCall(
              entry.emit(
                UncheckedCast(
                  entry.emit(DirectCall(lookup, [entry.parameters.first])),
                  instruction.callbackType,
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
            'callbackAddress${callbacks.length}',
            .integer,
            [],
          );
          externals.add(IrExternal(address));
          callbacks[instruction] = (
            address: address,
            target: _needsBridge(instruction.signature)
                ? _bridge(target, intoDart: true)
                : target,
          );
        }
      }
    }
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
