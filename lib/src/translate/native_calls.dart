import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/native.dart';

import 'builder.dart';
import 'conversions.dart';
import 'native_values.dart';
import 'scope.dart';
import 'types.dart';

/// Makes calls of functions of C.
final class NativeCalls(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  late final _conversions = Conversions(_scope, _builder);
  late final _values = NativeValues(_scope, _builder);

  HirValue _number(int value) => _builder.add(HirConst(value));

  HirValue _at(HirValue address, int offset) =>
      _builder.add(HirIntBinary(.add, address, _number(offset)));

  /// Calls the function at [address], which is of [signature], with values of
  /// [types], giving a result of [resultType].
  HirValue? call(
    HirValue address,
    NativeSignature signature,
    List<HirValue> arguments,
    List<DartType> types,
    DartType resultType,
  ) {
    final passing = _scope.natives.types.passing(signature);
    // Nothing is created once the block is being filled in.
    final ready = [
      for (final (i, type) in signature.parameters.indexed)
        _values.prepare(
          arguments[i],
          type,
          isByAddress: passing.parameters[i] is ByAddress,
        ),
    ];
    final result = passing.result;
    final resultMemory = result is ByAddress
        ? _values.newMemory(signature.result)
        : null;
    final block = _builder.add(HirMachine(.callBlock, const []));
    void store(int place, HirValue value) =>
        _builder.add(HirMachine(.store64, [_at(block, place), value]));
    for (final (i, type) in signature.parameters.indexed) {
      _values.store(block, passing.parameters[i], type, ready[i]);
    }
    if (result is ByAddress) {
      store(result.place, _values.addressOf(resultMemory!));
    }
    store(CallBlock.target, address);
    store(CallBlock.stackBytes, _number(passing.stackBytes));
    _builder.add(HirMachine(.callNative, [block]));
    // What the function was given stays until here.
    for (final value in [...arguments, ...ready, ?resultMemory]) {
      if (value.type != .reference) continue;
      _builder.add(HirMachine(.addressOf, [value]));
    }
    if (signature.result is NativeVoid) return null;
    return resultMemory != null
        ? _values.wrap(resultMemory, resultType)
        : _values.load(block, result, signature.result, resultType);
  }

  /// Does what a function that is declared as [declared], and calls the one of
  /// C at [address], does with the values that it was given.
  void forward(
    HirValue address,
    NativeSignature signature,
    List<HirValue> arguments,
    FunctionType declared,
  ) {
    final result = call(address, signature, arguments, [
      for (final parameter in declared.formalParameters) parameter.type,
    ], declared.returnType);
    final type = _builder.function.result;
    if (type == null) return _builder.end(HirReturn());
    final value = result ?? _builder.add(HirNull());
    _builder.end(HirReturn(_conversions.coerce(value, type)));
  }
}

/// The parameters of [type] as functions take them.
List<HirType>? parameterTypes(FunctionType type) {
  final found = [for (final p in type.formalParameters) valueType(p.type)];
  return found.contains(null) ? null : found.nonNulls.toList();
}
