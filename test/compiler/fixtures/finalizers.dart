import 'dart:async';
import 'dart:collection';
import 'dart:ffi';

import 'package:dartc/interop.dart';

final class Cell(final double value);

Finalizer<double?>? owner;
Cell? retained;
Object? key;
double total = 0;
int deliveries = 0;
int sequence = 0;

@Export<Void Function(Double, Int8)>()
void create(double value, int keep) {
  total = 0;
  deliveries = 0;
  sequence = 0;
  owner = Finalizer<double?>((token) {
    sequence = sequence * 10 + 3;
    total += token ?? 10.0;
    deliveries++;
    scheduleMicrotask(() {
      sequence = sequence * 10 + 4;
    });
    churn(20000);
  });
  final target = Cell(value);
  key = Object();
  owner!.attach(target, value, detach: key);
  retained = keep == 0 ? null : target;
}

@Export<Double Function(Int64)>()
double churn(int count) {
  var sum = 0.0;
  for (var i = 0; i < count; i++) {
    sum += Cell(i.toDouble()).value;
  }
  return sum;
}

@Export<Int64 Function(Int8)>()
int collect(int cancel) {
  churn(20000);
  sequence = sequence * 10 + 1;
  scheduleMicrotask(() {
    if (cancel != 0) owner!.detach(key!);
    sequence = sequence * 10 + 2;
  });
  return deliveries;
}

@Export<Void Function()>()
void release() => retained = null;

@Export<Double Function()>()
double read() => total;

@Export<Int64 Function()>()
int order() => sequence;

@Export<Int64 Function()>()
int count() => deliveries;

@Export<Void Function()>()
void createInZone() {
  total = 0;
  deliveries = 0;
  sequence = 0;
  runZonedGuarded(
    () {
      owner = Finalizer<double?>((value) {
        total = (Zone.current['value'] as double) + (value ?? 10.0);
        deliveries++;
        throw StateError('callback');
      });
      owner!.attach(Cell(1), null);
    },
    (error, trace) {
      if (error is StateError) sequence = 7;
    },
    zoneValues: {'value': 2.5},
  );
}

@Export<Void Function()>()
void discardOwner() => owner = null;

@Export<Int64 Function(Pointer<NativeFunction<Void Function()>>)>()
int reenter(Pointer<NativeFunction<Void Function()>> callback) {
  churn(20000);
  callback.asFunction<void Function()>()();
  return deliveries;
}

@Export<Int8 Function(Int8, Int8)>()
int rejects(int kind, int detach) {
  final Object value = switch (kind) {
    0 => 1,
    1 => 1.25,
    2 => true,
    3 => 'key',
    _ => Pointer<Void>.fromAddress(1234),
  };
  final finalizer = Finalizer<Object?>((_) {});
  try {
    finalizer.attach(
      detach == 0 ? value : Object(),
      null,
      detach: detach == 0 ? null : value,
    );
    return 0;
  } on ArgumentError catch (error) {
    return identical(error.invalidValue, value) &&
            error.name == (detach == 0 ? 'value' : 'detach')
        ? 1
        : -1;
  }
}

@Export<Void Function()>()
void timers() {
  sequence = 0;
  final cancelled = Timer(const Duration(days: 1), () => sequence = -1);
  Timer(const Duration(microseconds: -1), cancelled.cancel);
  Timer.run(() {
    sequence = sequence * 10 + 2;
    scheduleMicrotask(() => sequence = sequence * 10 + 3);
  });
  Timer(const Duration(milliseconds: 2), () => sequence = sequence * 10 + 4);
  scheduleMicrotask(() => sequence = 1);
}

@Export<Void Function()>()
void periodic() {
  deliveries = 0;
  Timer.periodic(Duration.zero, (timer) {
    if (!timer.isActive || timer.tick != deliveries + 1) {
      throw StateError('periodic timer state');
    }
    deliveries++;
    if (deliveries == 3) {
      timer.cancel();
      if (timer.isActive) throw StateError('cancelled timer');
    }
    churn(20000);
  });
}

@Export<Int64 Function()>()
int zoneMaps() {
  final map = HashMap<int, String>(
    equals: (a, b) => a % 10 == b % 10,
    hashCode: (a) => a % 10,
    isValidKey: (key) => key is int,
  );
  final Object foreignKey = '1';
  map[1] = 'first';
  map[11] = 'second';
  final identity = HashMap<Object, int>.identity();
  final a = Cell(1), b = Cell(1);
  identity[a] = 1;
  identity[b] = 2;
  const constants = <String, int>{'first': 1, 'second': 2};
  final same = identical(constants, const {'first': 1, 'second': 2});
  var immutable = false;
  try {
    constants['third'] = 3;
  } on UnsupportedError {
    immutable = true;
  }
  return map.length == 1 &&
          map[21] == 'second' &&
          map[foreignKey] == null &&
          map.keys.single == 1 &&
          map.remove(31) == 'second' &&
          map.isEmpty &&
          identity.length == 2 &&
          identity[a] == 1 &&
          identity[b] == 2 &&
          constants['second'] == 2 &&
          constants.containsKey('first') &&
          same &&
          immutable
      ? 1
      : 0;
}

@Export<Void Function()>()
void multiple() {
  create(1.25, 1);
  owner!.attach(retained!, 2.5);
  owner!.attach(retained!, null);
  release();
}
