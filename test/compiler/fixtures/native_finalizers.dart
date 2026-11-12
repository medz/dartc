import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/interop.dart';

NativeFinalizer? owner;
Pointer<NativeFinalizerFunction>? savedCallback;
Resource? retained;
List<Resource>? resources;
TypedData? nativeView;
Pointer<Int64> Function()? closure;
int observed = -1;

final class Resource(final Pointer<Int64> pointer) implements Finalizable {
  this {
    owner!.attach(this, pointer.cast(), detach: this, externalSize: 64);
  }
  int readAfterWork() {
    final address = pointer;
    churn();
    return address.value;
  }
}

void churn() {
  for (var i = 0; i < 20000; i++) {
    Uint8List(64);
  }
}

@Export<Void Function(Pointer<NativeFinalizerFunction>)>()
void configure(Pointer<NativeFinalizerFunction> callback) {
  owner = NativeFinalizer(callback);
  if (owner!.callback != callback) {
    throw StateError('Finalizer callback changed');
  }
  savedCallback = callback;
  retained = null;
  resources = null;
  nativeView = null;
  closure = null;
}

@Export<Int64 Function(Pointer<Int64>, Int32)>()
int lifetimes(Pointer<Int64> state, int mode) {
  switch (mode) {
    case 0:
      var during = -1;
      {
        final resource = Resource(state);
        final address = resource.pointer;
        churn();
        during = address.value;
      }
      churn();
      return during * 10 + state.value;
    case 1:
      return parameter(Resource(state));
    case 2:
      return Resource(state).readAfterWork();
    case 3:
      final resource = Resource(state);
      closure = () {
        final address = resource.pointer;
        churn();
        return address;
      };
      return 0;
    case 4:
      try {
        final resource = Resource(state);
        failAfterWork(resource.pointer);
      } on StateError {
        return observed;
      }
    case 5:
      late Resource resource;
      closure = () => resource.pointer;
      churn();
      resource = Resource(state);
      return 0;
    case 7:
      Resource? resource = Resource(state);
      final address = resource.pointer;
      resource = null;
      churn();
      return address.value;
    default:
      Resource? resource = Resource(state);
      final address = resource.pointer;
      resource = replaceAfterWork(address);
      return observed;
  }
}

int parameter<T extends Finalizable>(T resource) {
  final address = (resource as Resource).pointer;
  churn();
  return address.value;
}

Never failAfterWork(Pointer<Int64> address) {
  churn();
  observed = address.value;
  throw StateError('finished');
}

Resource? replaceAfterWork(Pointer<Int64> address) {
  churn();
  observed = address.value;
  return null;
}

@Export<Int64 Function(Pointer<Int64>)>()
int collect(Pointer<Int64> state) {
  churn();
  return state.value;
}

@Export<Int64 Function()>()
int callClosure() => closure!().value;

@Export<Void Function()>()
void releaseClosure() => closure = null;

@Export<Void Function(Pointer<Int64>, Int32)>()
void attach(Pointer<Int64> state, int mode) {
  if (mode == 4) {
    resources = [];
    for (var i = 0; i < 1000; i++) {
      owner = NativeFinalizer(savedCallback!);
      resources!.add(Resource(state));
    }
    return;
  }
  final resource = Resource(state);
  if (mode == 0) retained = resource;
  if (mode == 1) owner!.detach(resource);
  if (mode == 2) owner!.attach(resource, state.cast());
  if (mode == 3) owner = null;
}

@Export<Bool Function(Pointer<Int64>, Int64)>()
bool invalidSize(Pointer<Int64> state, int size) {
  final resource = Resource(state);
  owner!.detach(resource);
  try {
    owner!.attach(resource, state.cast(), externalSize: size);
  } on ArgumentError {
    return true;
  }
  return false;
}

@Export<Int64 Function(Pointer<Int64>, Int32)>()
int pointerViews(Pointer<Int64> state, int mode) {
  switch (mode) {
    case 0:
      final values = (state + 1).cast<Int16>().asTypedList(
        4,
        finalizer: savedCallback,
        token: state.cast(),
      );
      values[1] = -123;
      nativeView = Int16List.sublistView(values, 1);
      return 0;
    case 1:
      churn();
      return (nativeView as Int16List)[0];
    case 2:
      nativeView = null;
      churn();
      return state.value;
    case 3:
      nativeView = state.asTypedList(1, finalizer: savedCallback);
      return 0;
    case 4:
      try {
        state.asTypedList(-1);
      } on ArgumentError {
        return 1;
      }
      return 0;
    default:
      final values = state.cast<Double>().asTypedList(2, finalizer: null);
      values[1] = -1.25;
      return (state + 1).cast<Double>().value == -1.25 ? 1 : 0;
  }
}
