import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'varargs_types.dart';

typedef EmptyFormat = Int Function(
  Pointer<Uint8>,
  Size,
  Pointer<Uint8>,
  VarArgs<()>,
);
typedef Format = Int Function(
  Pointer<Uint8>,
  Size,
  Pointer<Uint8>,
  VarArgs<(Int, Double, Pointer<Uint8>, Int64)>,
);
typedef DartFormat = int Function(
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
  double,
  Pointer<Uint8>,
  int,
);
typedef WideFormat = Int Function(
  Pointer<Uint8>,
  Size,
  Pointer<Uint8>,
  VarArgs<
    (
      Int,
      Double,
      Int,
      Double,
      Int,
      Double,
      Int,
      Double,
      Int,
      Double,
      Int,
      Double,
      Int,
      Double,
      Int,
      Double,
      Int,
      Double,
      Int,
      Double,
    )
  >,
);
typedef DartWideFormat = int Function(
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
  double,
  int,
  double,
  int,
  double,
  int,
  double,
  int,
  double,
  int,
  double,
  int,
  double,
  int,
  double,
  int,
  double,
  int,
  double,
);
typedef Callback = Double Function(Int, VarArgs<(Double, Int)>);
typedef DartCallback = double Function(int, double, int);

@Native<Format>(symbol: 'snprintf')
external int format(
  Pointer<Uint8> output,
  int size,
  Pointer<Uint8> pattern,
  int integer,
  double real,
  Pointer<Uint8> text,
  int wide,
);

@Export<Callback>(symbol: 'variadic_callback')
double sum(int first, double second, int third) => first + second + third;

double optional(int first, [double second = 0, int third = 0]) =>
    sum(first, second, third);

@Export<AggregateCallback>(symbol: 'variadic_aggregates')
double aggregates(int bias, Pair pair, Triple triple) =>
    bias + pair.x + pair.y + triple.a + triple.b + triple.c;

@Export<
  Double Function(Pointer<NativeFunction<AggregateCallback>>, Pair, Triple)
>(symbol: 'call_variadic_aggregates')
double callAggregates(
  Pointer<NativeFunction<AggregateCallback>> callback,
  Pair pair,
  Triple triple,
) => callback.asFunction<DartAggregateCallback>()(7, pair, triple);

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() => runVarargs();

void runVarargs({bool methodValues = true}) {
  final library = DynamicLibrary.process();
  final allocate = library
      .lookupFunction<
        Pointer<Uint8> Function(Size),
        Pointer<Uint8> Function(int)
      >('malloc');
  final free = library
      .lookupFunction<
        Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)
      >('free');
  final allocations = <Pointer<Uint8>>[];
  Pointer<Uint8> memory(int size) {
    final pointer = allocate(size);
    if (pointer == nullptr) throw StateError('allocation failed');
    allocations.add(pointer);
    return pointer;
  }

  Pointer<Uint8> text(String value) {
    final pointer = memory(value.length + 1);
    for (var i = 0; i < value.length; i++) {
      pointer[i] = value.codeUnitAt(i);
    }
    pointer[value.length] = 0;
    return pointer;
  }

  String read(Pointer<Uint8> pointer) {
    final units = <int>[];
    for (var i = 0; pointer[i] != 0; i++) {
      units.add(pointer[i]);
    }
    return String.fromCharCodes(units);
  }

  try {
    final output = memory(512);
    final pointer = library.lookup<NativeFunction<Format>>('snprintf');
    final invoke = pointer.asFunction<DartFormat>();
    final leaf = pointer.asFunction<DartFormat>(isLeaf: true);
    DartFormat? extracted;
    if (methodValues) {
      final extract = pointer.asFunction;
      extracted = extract<DartFormat>();
    }
    final pattern = text('%d %.2f %s %lld');
    final word = text('Dart');
    for (final call in [invoke, leaf, ?extracted, format]) {
      final length = call(output, 512, pattern, -17, 2.25, word, 12345678901);
      const expected = '-17 2.25 Dart 12345678901';
      check(length == expected.length, 'result length');
      check(read(output) == expected, 'mixed arguments and native writes');
      check(
        call(output, 5, pattern, -17, 2.25, word, 12345678901) == length,
        'truncated length',
      );
      check(read(output) == '-17 ', 'bounded write');
    }
    final empty = library
        .lookupFunction<
          EmptyFormat,
          int Function(Pointer<Uint8>, int, Pointer<Uint8>)
        >('snprintf');
    check(empty(output, 512, text('no arguments')) == 12, 'empty VarArgs');
    check(read(output) == 'no arguments', 'empty output');
    final wide = pointer
        .cast<NativeFunction<WideFormat>>()
        .asFunction<DartWideFormat>();
    final widePattern = text(
      '%d:%.1f %d:%.1f %d:%.1f %d:%.1f %d:%.1f %d:%.1f %d:%.1f %d:%.1f %d:%.1f %d:%.1f',
    );
    const expected =
        '1:1.5 2:2.5 3:3.5 4:4.5 5:5.5 6:6.5 7:7.5 8:8.5 9:9.5 10:10.5';
    check(
      wide(
            output,
            512,
            widePattern,
            1,
            1.5,
            2,
            2.5,
            3,
            3.5,
            4,
            4.5,
            5,
            5.5,
            6,
            6.5,
            7,
            7.5,
            8,
            8.5,
            9,
            9.5,
            10,
            10.5,
          ) ==
          expected.length,
      'register exhaustion length',
    );
    check(read(output) == expected, 'both register banks and stack');
    final callback = NativeCallable<Callback>.isolateLocal(
      (int a, double b, int c) => sum(a, b, c) + 0.5,
      exceptionalReturn: -1.0,
    );
    try {
      check(
        callback.nativeFunction.asFunction<DartCallback>()(3, 1.25, 7) == 11.75,
        'variadic closure callback',
      );
    } finally {
      callback.close();
    }
    check(
      Pointer.fromFunction<Callback>(sum, -1.0).asFunction<DartCallback>()(
            3,
            1.25,
            7,
          ) ==
          11.25,
      'variadic static callback',
    );
    check(
      Pointer.fromFunction<Callback>(
            // Analyzer 14.7 rejects compatible optional callback parameters.
            // ignore: must_be_a_subtype
            optional,
            -1.0,
          ).asFunction<DartCallback>()(3, 1.25, 7) ==
          11.25,
      'optional variadic callback',
    );
    print(
      'varargs: formatting, stack arguments, side effects and callbacks passed',
    );
  } finally {
    for (final pointer in allocations) {
      free(pointer);
    }
  }
}
