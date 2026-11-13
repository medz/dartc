import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'dynamic_library_types.dart';

typedef NativeBlend = Double Function(Double, Double);
typedef Blend = double Function(double, double);
const leaf = 1 + 1 == 2;

@Export<Double Function(Double)>(symbol: 'dartc_library_self')
double localValue(double value) => value + 3.5;

int effects = 0;
DynamicLibrary? absent;

DynamicLibrary receiver(DynamicLibrary library) {
  effects = effects * 10 + 1;
  return library;
}

String symbol() {
  effects = effects * 10 + 2;
  return 'blend';
}

void check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

void fails<T>(void Function() action) {
  try {
    action();
  } catch (error) {
    if (error is T) return;
    rethrow;
  }
  throw StateError('Expected $T');
}

void main() => runLibraries(dartc: true);

void runLibraries({bool dartc = false}) {
  final abi = Abi.current();
  final target = abi.toString().replaceAll('_', '-');
  final extension = abi == Abi.macosArm64 || abi == Abi.macosX64
      ? 'dylib'
      : 'so';
  final path =
      'build/test/$target/compiler/dynamic_library_provider.$extension';
  final first = DynamicLibrary.open(path);
  final second = DynamicLibrary.open(path);
  check(first == second && !identical(first, second), 'handle identity');
  check(
    first.hashCode == second.hashCode && first.handle == second.handle,
    'handle values',
  );
  check(first != Object(), 'unrelated equality');
  check(first.providesSymbol('blend'), 'present symbol');
  check(!first.providesSymbol('missing_dartc_symbol'), 'missing symbol');
  fails<ArgumentError>(() => first.lookup<Void>('missing_dartc_symbol'));

  final blend = receiver(first).lookupFunction<NativeBlend, Blend>(symbol());
  check(effects == 12, 'lookup evaluation order');
  check(blend(1.25, 2.5) == 6.25, 'floating function');
  final leafBlend = DynamicLibraryExtension(first)
      .lookupFunction<NativeBlend, Blend>('blend', isLeaf: leaf);
  check(leafBlend(-2.5, 3.25) == 4, 'leaf function');
  check(
    first.lookup<NativeFunction<NativeBlend>>('blend').asFunction<Blend>()(
          2,
          3,
        ) ==
        8,
    'typed lookup',
  );
  final pointer = first
      .lookupFunction<
        Pointer<Double> Function(Pointer<Double>),
        Pointer<Double> Function(Pointer<Double>)
      >('identity');
  check(
    pointer(Pointer.fromAddress(0x12340)).address == 0x12340,
    'pointer function',
  );
  final transform = first
      .lookupFunction<
        LibraryValue Function(LibraryValue, Bool),
        LibraryValue Function(LibraryValue, bool)
      >('transform');
  final input = Struct.create<LibraryValue>()
    ..tag = -3
    ..value = 1.25;
  final output = transform(input, true);
  check(output.tag == 4 && output.value == -2.5, 'compound return');
  check(input.tag == -3 && input.value == 1.25, 'compound passed by value');
  final callback = NativeCallable<Double Function(Double)>.isolateLocal(
    (double value) => value + input.value,
    exceptionalReturn: -1.0,
  );
  try {
    final invoke = first
        .lookupFunction<
          Double Function(
            Pointer<NativeFunction<Double Function(Double)>>,
            Double,
          ),
          double Function(
            Pointer<NativeFunction<Double Function(Double)>>,
            double,
          )
        >('invoke');
    check(
      invoke(callback.nativeFunction, 2.5) == 4.25,
      'managed callback reentry',
    );
  } finally {
    callback.close();
  }

  check(
    absent?.lookupFunction<NativeBlend, Blend>(symbol()) == null &&
        effects == 12,
    'null-aware lookup',
  );
  first.close();
  first.close();
  fails<StateError>(() => first.lookup<Void>('blend'));
  if (dartc) {
    fails<StateError>(() => first.providesSymbol('blend'));
    fails<ArgumentError>(() => second.lookup<Void>('blend\u0000other'));
    fails<ArgumentError>(() => DynamicLibrary.open('$path\u0000other'));
  }
  check(blend(1, 2) == 5, 'second handle keeps captured function alive');
  check(
    first == second && first.handle == second.handle,
    'closed handle identity',
  );
  second.close();

  final reopened = DynamicLibrary.open(path);
  check(
    reopened.lookupFunction<NativeBlend, Blend>('blend')(3, 4) == 11,
    'reopen',
  );
  reopened.close();
  final unicode = DynamicLibrary.open(
    'build/test/$target/compiler/动态库.$extension',
  );
  check(unicode.providesSymbol('blend'), 'UTF-8 library path');
  check(!unicode.providesSymbol('不存在'), 'UTF-8 symbol');
  unicode.close();
  fails<ArgumentError>(() => DynamicLibrary.open('$path.missing'));

  final process = DynamicLibrary.process();
  final executable = DynamicLibrary.executable();
  check(process == DynamicLibrary.process(), 'process identity');
  check(executable == DynamicLibrary.executable(), 'executable identity');
  for (final library in [process, executable]) {
    if (dartc) {
      final local = library
          .lookupFunction<Double Function(Double), double Function(double)>(
            'dartc_library_self',
          );
      check(local(1.25) == 4.75, 'executable exports');
    }
    check(library.providesSymbol('malloc'), 'system symbol');
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
    final memory = allocate(4);
    check(memory != nullptr, 'system allocation');
    memory[0] = 239;
    check(memory[0] == 239, 'loaded memory access');
    free(memory);
    fails<StateError>(library.close);
    check(library.providesSymbol('malloc'), 'failed close preserves handle');
  }
  print(
    'dynamic libraries: typed calls, callbacks, identity and lifetime passed',
  );
}
