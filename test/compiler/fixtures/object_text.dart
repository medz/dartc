import 'dart:async';
import 'dart:ffi';

import 'package:dartc/interop.dart';

import '../../frontend/lowering/fixtures/dynamic_dispatch.dart' as dynamic_sdk;
import '../../frontend/lowering/fixtures/dynamic_dispatch_private_use.dart'
    as private_sdk;
import '../../frontend/lowering/fixtures/effects.dart' as effects;

import 'core_collections.dart';
import 'core_conversion.dart';

// FFI storage subclasses cannot declare generative constructors.
// ignore: use_primary_constructors
final class ParsedNumber extends Struct {
  @Double()
  external double floating;

  @Int64()
  external int integer;
}

num? parseNumber(String source, int mode) => switch (mode) {
  0 => double.parse(source),
  1 => double.tryParse(source),
  2 => double.parse.call(source),
  3 => double.tryParse.call(source),
  4 => num.parse(source),
  5 => num.tryParse(source),
  6 => num.parse.call(source),
  _ => num.tryParse.call(source),
};

@Export<Int32 Function(Pointer<Uint16>, IntPtr, Int32, Pointer<ParsedNumber>)>()
int parseBuffer(
  Pointer<Uint16> input,
  int length,
  int mode,
  Pointer<ParsedNumber> output,
) {
  final source = String.fromCharCodes(input.asTypedList(length));
  try {
    final value = parseNumber(source, mode);
    if (value == null) return 2;
    if (value is int) {
      output.ref.integer = value;
      return 1;
    }
    output.ref.floating = value.toDouble();
    return 0;
  } on FormatException catch (error) {
    return mode >= 4 || identical(error.source, source) ? 3 : 9;
  }
}

String formatDouble(double value, int mode, int digits) => switch (mode) {
  0 => value.toString(),
  1 => value.toStringAsFixed(digits),
  2 => value.toStringAsExponential(digits),
  4 => value.toStringAsExponential(),
  5 => value.toStringAsFixed.call(digits),
  6 => value.toStringAsPrecision.call(digits),
  _ => value.toStringAsPrecision(digits),
};

@Export<Int32 Function(Double, Int32, Int32, Pointer<Uint16>, IntPtr)>()
int formatBuffer(
  double value,
  int mode,
  int digits,
  Pointer<Uint16> output,
  int capacity,
) {
  try {
    return _write(formatDouble(value, mode, digits), output, capacity);
  } on RangeError {
    return -1;
  } catch (error) {
    return _write('Unexpected error: $error', output, capacity);
  }
}

@Export<Int32 Function(Int32, Pointer<Uint16>, IntPtr)>()
int collectionBuffer(int mode, Pointer<Uint16> output, int capacity) =>
    _write(collectionText(mode), output, capacity);

typedef OptionalText = String Function(int, [bool]);
typedef NamedText = int Function({required String name, double value});
typedef GenericText = T Function<T extends num>(T);
typedef NullableText = String Function()?;
typedef NestedText = T Function<T extends num>(U Function<U extends T>(U, T));

class TypeBox<T>() {
  String describe() => '$T|${List<T>}';
}

String typeText(int mode) => switch (mode) {
  0 => (int).toString(),
  1 => (null as Object?).runtimeType.toString(),
  2 => '$dynamic|${typeOf<void>()}',
  3 => '${List<Map<String, int?>>}',
  4 => (OptionalText).toString(),
  5 => (NamedText).toString(),
  6 => (GenericText).toString(),
  7 => (NullableText).toString(),
  8 => '${typeOf<(int, String)>()}',
  9 => '${typeOf<({int count, String label})>()}',
  10 => TypeBox<String?>().describe(),
  11 => '${FutureOr<int>}',
  12 => (NestedText).toString(),
  13 => '${typeOf<(int,)>()}',
  14 => '${typeOf<(int, {String label})?>()}',
  _ => '$Never',
};
@Export<Int32 Function(Int32, Pointer<Uint16>, IntPtr)>()
int typeBuffer(int mode, Pointer<Uint16> output, int capacity) =>
    _write(typeText(mode), output, capacity);

Type typeOf<T>() => T;

String dispatchText(int mode) {
  effects.calls.clear();
  final Object? result = switch (mode) {
    0 => dynamic_sdk.named(),
    >= 1 && <= 5 => dynamic_sdk.getterOrder(mode - 1),
    >= 6 && <= 12 => dynamic_sdk.calls(mode - 6),
    13 || 14 => dynamic_sdk.updates(mode == 14),
    >= 15 && <= 17 => dynamic_sdk.genericCalls(mode - 15),
    >= 18 && <= 22 => dynamic_sdk.failures(mode - 18),
    >= 23 && <= 26 => dynamic_sdk.fallback(mode - 23),
    27 => dynamic_sdk.objectMembers(),
    >= 28 && <= 33 => dynamic_sdk.boundedCalls(mode - 28),
    >= 34 && <= 37 => dynamic_sdk.getterFailures(mode - 34),
    38 => dynamic_sdk.operators(7),
    39 => dynamic_sdk.userOperators(),
    40 => dynamic_sdk.objectTearoffs(),
    41 => dynamic_sdk.genericEnvironments(),
    42 => dynamic_sdk.invocationData(),
    43 => private_sdk.privateLibraries(),
    >= 44 && < 58 => dynamic_sdk.binary(7, mode - 44),
    58 || 59 => dynamic_sdk.nullAssignments(mode == 59),
    60 || 61 => dynamic_sdk.nullIndex(mode == 61),
    62 || 63 => dynamic_sdk.functionCascade(mode == 63),
    64 || 65 => dynamic_sdk.nullChain(mode == 65),
    66 => dynamic_sdk.customEquality(),
    67 => dynamic_sdk.shapeBeforeBounds(),
    >= 68 && < 74 => dynamicNumeric(mode - 68),
    74 => dynamicScalarMethods(),
    75 => dynamicCollections(),
    _ => throw RangeError.value(mode),
  };
  return '$result|${effects.calls}';
}

@Export<Int32 Function(Int32, Pointer<Uint16>, IntPtr)>()
int dispatchBuffer(int mode, Pointer<Uint16> output, int capacity) =>
    _write(dispatchText(mode), output, capacity);

@Export<
  Int32 Function(
    Pointer<Uint16>,
    IntPtr,
    Int32,
    IntPtr,
    Pointer<Uint16>,
    IntPtr,
  )
>()
int conversionBuffer(
  Pointer<Uint16> source,
  int length,
  int mode,
  int split,
  Pointer<Uint16> output,
  int capacity,
) => _write(
  conversionText(
    String.fromCharCodes(source.asTypedList(length)),
    Conversion.values[mode],
    split,
  ),
  output,
  capacity,
);

int _write(String text, Pointer<Uint16> output, int capacity) {
  if (text.length > capacity) return -2;
  output.asTypedList(text.length).setAll(0, text.codeUnits);
  return text.length;
}

String dynamicNumeric(int mode) {
  dynamic left = mode.isEven ? -7.5 : -7;
  dynamic right = 2.0;
  return switch (mode) {
    0 || 1 => '${left % right}',
    2 || 3 => '${left.remainder(right)}',
    4 => '${(-7.5) % 2}|${7 % -2.5}',
    _ => '${(-7).remainder(2.5)}|${7.5.remainder(-2)}',
  };
}

String dynamicScalarMethods() {
  dynamic integer = 42, floating = 1.25, boolean = true;
  final integerText = integer.toRadixString;
  final floatingText = floating.toStringAsFixed;
  final booleanText = boolean.toString;
  return '${integerText(16)}|${floatingText(2)}|${booleanText()}';
}

String dynamicCollections() {
  dynamic list = <int>[1, 2], map = <String, int>{}, text = 'abc';
  list.add(3);
  map['key'] = list[1];
  final join = list.join;
  return '${join('-')}|${map['key']}|${text.substring(1)}';
}
