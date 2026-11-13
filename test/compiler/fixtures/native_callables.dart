import 'dart:async';
import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'native_callbacks.dart' show CallbackState, Change, Mixed, Unary;

final _handles = <NativeCallable<Function>>[];
WeakReference<List<int>>? _weak;

void collect() {
  for (var i = 0; i < 3000; i++) {
    final values = List<int>.filled(16, i);
    if (values.last != i) throw StateError('lost allocation');
  }
}

@Export<Pointer<NativeFunction<Unary>> Function(Int64)>()
Pointer<NativeFunction<Unary>> create(int value) {
  final state = [value];
  _weak = WeakReference(state);
  final callback = NativeCallable<Unary>.isolateLocal((int input) {
    collect();
    if (input < 0) throw StateError('callback error');
    return state.single + input;
  }, exceptionalReturn: -41);
  _handles.add(callback);
  return callback.nativeFunction;
}

@Export<Bool Function()>()
bool releaseLast() {
  final callback = _handles.removeLast();
  callback.close();
  callback.close();
  callback.keepIsolateAlive = true;
  if (callback.keepIsolateAlive) return false;
  try {
    callback.nativeFunction;
    return false;
  } on StateError {
    collect();
    return _weak!.target == null;
  }
}

@Export<Void Function()>()
void closeAll() {
  for (final callback in _handles) {
    callback.close();
  }
  _handles.clear();
}

@Export<Pointer<NativeFunction<Mixed>> Function(Double)>()
Pointer<NativeFunction<Mixed>> mixed(double bias) {
  final callback = NativeCallable<Mixed>.isolateLocal((
    int a,
    double b,
    bool c,
    double d,
    int e,
    int f,
    int g,
    int h,
    int i,
    int j,
    int k,
    int l,
    int m,
  ) {
    if (!c) throw StateError('mixed failure');
    return bias + a + b + d + e + f + g + h + i + j + k + l + m;
  }, exceptionalReturn: -1.25);
  _handles.add(callback);
  return callback.nativeFunction;
}

@Export<Pointer<NativeFunction<Change>> Function(Int64)>()
Pointer<NativeFunction<Change>> compound(int increment) {
  final callback = NativeCallable<Change>.isolateLocal((
    CallbackState state,
    bool fail,
  ) {
    if (fail) throw StateError('compound failure');
    state.count += increment;
    state.value *= 2;
    state.entries[1] += state.entries[0];
    return state;
  });
  _handles.add(callback);
  return callback.nativeFunction;
}

@Export<
  Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>> Function()
>()
Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>> threadEntry() {
  final state = [1];
  final callback =
      NativeCallable<Pointer<Void> Function(Pointer<Void>)>.isolateLocal((
        Pointer<Void> pointer,
      ) {
        state.add(2);
        return pointer;
      });
  _handles.add(callback);
  return callback.nativeFunction;
}

int optional(int value, [int extra = 3]) => value + extra;
int named(int value, {int extra = 4}) => value + extra;
int allOptional([int value = 2, int extra = 3]) => value + extra;

void main() {
  final staticCall = Pointer.fromFunction<Unary>(
    // ignore: must_be_a_subtype
    optional,
    -1,
  ).asFunction<int Function(int)>();
  if (staticCall(2) != 5) throw StateError('static defaults');
  final defaults = NativeCallable<Unary>.isolateLocal(
    // ignore: must_be_a_subtype
    named,
    exceptionalReturn: -1,
  );
  if (defaults.nativeFunction.asFunction<int Function(int)>()(2) != 6) {
    throw StateError('closure defaults');
  }
  defaults.close();
  final supplied = Pointer.fromFunction<Int64 Function(Int64, Int64)>(
    // ignore: must_be_a_subtype
    optional,
    -1,
  ).asFunction<int Function(int, int)>();
  if (supplied(2, 7) != 9) throw StateError('supplied optional parameter');
  final empty = Pointer.fromFunction<Int64 Function()>(
    // ignore: must_be_a_subtype
    allOptional,
    -1,
  ).asFunction<int Function()>();
  if (empty() != 5) throw StateError('all optional parameters');
  final captured = 7;
  final closureDefaults = NativeCallable<Unary>.isolateLocal(
    // ignore: must_be_a_subtype
    (int value, {int extra = 4}) => value + extra + captured,
    exceptionalReturn: -1,
  );
  if (closureDefaults.nativeFunction.asFunction<int Function(int)>()(2) != 13) {
    throw StateError('captured optional parameter');
  }
  closureDefaults.close();
  final calls = <NativeCallable<Unary>>[];
  for (var i = 0; i < 4097; i++) {
    calls.add(
      NativeCallable<Unary>.isolateLocal(
        (int value) => value + i,
        exceptionalReturn: -1,
      ),
    );
  }
  for (final index in [0, 2048, 4096]) {
    if (calls[index].nativeFunction.asFunction<int Function(int)>()(7) !=
        index + 7) {
      throw StateError('distinct callback state');
    }
  }
  for (final call in calls) {
    call.close();
  }
  final retained = [17];
  late NativeCallable<Unary> closing;
  closing = NativeCallable<Unary>.isolateLocal((int value) {
    closing.close();
    final replacement = NativeCallable<Unary>.isolateLocal(
      (int value) => value + 100,
      exceptionalReturn: -1,
    );
    try {
      collect();
      return retained.single +
          replacement.nativeFunction.asFunction<int Function(int)>()(value);
    } finally {
      replacement.close();
    }
  }, exceptionalReturn: -1);
  if (closing.nativeFunction.asFunction<int Function(int)>()(2) != 119) {
    throw StateError('close during callback');
  }
  final timer = NativeCallable<Unary>.isolateLocal(
    (int value) => value,
    exceptionalReturn: -1,
  );
  Timer.run(() {
    timer.close();
    print('native_callables:ok');
  });
}
