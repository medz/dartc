import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

/// Checks native bindings and exposes pointer conversions as ordinary IR calls.
final class NativeBindings(
  IrProgram source,
  Map<FunctionTarget, NativeImport> sourceImports,
  Map<FunctionTarget, NativeExport> sourceExports,
) {
  late final IrProgram program;
  final definitions = <FunctionTarget>{};
  final imports = <FunctionTarget, NativeImport>{};
  final exports = <FunctionTarget, NativeExport>{};
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
      if (_hasPointers(binding.signature)) {
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
      if (target.typeParameters.isNotEmpty ||
          signature.parameters.length != target.parameterTypes.length ||
          target.returnType != FfiTypes.valueType(signature.result) ||
          !target.parameterTypes.indexed.every(
            (p) => p.$2 == FfiTypes.valueType(signature.parameters[p.$1]),
          )) {
        throw ArgumentError('Native signature mismatch: ${target.name}');
      }
      exports[_hasPointers(signature)
              ? _bridge(target, intoDart: true)
              : target] =
          binding;
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

  bool _hasPointers(NativeSignature signature) =>
      signature.result is NativePointerType ||
      signature.parameters.any((type) => type is NativePointerType);

  FunctionTarget _bridge(FunctionTarget dart, {required bool intoDart}) {
    ValueType rawType(ValueType type) =>
        FfiTypes.isPointer(type) ? .integer : type;
    final raw = FunctionTarget(
      null,
      'native${_functions.length}',
      rawType(dart.returnType),
      dart.parameterTypes.map(rawType),
    );
    definitions.add(raw);
    final (source, destination) = intoDart ? (raw, dart) : (dart, raw);
    final entry = Block(source.parameterTypes);
    final arguments = [
      for (final (i, value) in entry.parameters.indexed)
        if (FfiTypes.isPointer(dart.parameterTypes[i]))
          entry.emit(
            intoDart
                ? PointerFromAddress(value, dart.parameterTypes[i] as ClassType)
                : PointerAddress(value),
          )
        else
          value,
    ];
    Value result = entry.emit(DirectCall(destination, arguments));
    if (FfiTypes.isPointer(dart.returnType)) {
      result = entry.emit(
        intoDart
            ? PointerAddress(result)
            : PointerFromAddress(result, dart.returnType as ClassType),
      );
    }
    entry.finish(Return(result));
    _functions.add(IrFunction(source, [entry]));
    return raw;
  }
}
