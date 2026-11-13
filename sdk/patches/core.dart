import 'dart:_internal' show checkValidWeakTarget;
import 'dart:async' as async;

import '../../lib/runtime/contracts.dart' as runtime;
import '../runtime/allocator.dart' as allocator;
import '../runtime/finalization.dart' as finalization;
import '../runtime/memory.dart';
import '../runtime/type_info.dart' as metadata;
import '../runtime/stack_trace.dart' as traces;
import 'date_time.dart' as dates;

@patch
class Finalizer<T> {
  @patch
  factory Finalizer(void Function(T) callback) => _Finalizer<T>(callback);
}

final class _Finalizer<T>(void Function(T) callback)
    extends finalization.FinalizerHandle<T>
    implements Finalizer<T> {
  this
    : super(
        allocator.events().finalizers,
        async.Zone.current.bindUnaryCallbackGuarded(callback),
      );

  @override
  void attach(Object value, T finalizationToken, {Object? detach}) {
    checkValidWeakTarget(value, 'value');
    if (detach != null) checkValidWeakTarget(detach, 'detach');
    super.attach(value, finalizationToken, detach: detach);
  }
}

@patch
class Object {
  external int get _identityHashCode;

  @patch
  dynamic noSuchMethod(Invocation invocation) =>
      throw NoSuchMethodError.withInvocation(this, invocation);

  @runtime.Primitive(.className)
  external String get _className;

  static String _toString(Object? object) =>
      object == null ? 'null' : "Instance of '${object._className}'";

  @patch
  String toString() => "Instance of '" + _className + "'";
}

@patch
class Error {
  @patch
  @pragma(
    'dartc:patch',
    'storage: error traces are recorded by the target unwinder',
  )
  StackTrace? get stackTrace => traces.errorTrace(this);
}

@patch
class StackTrace {
  @patch
  static StackTrace get current => traces.currentStackTrace();
}

@patch
class DateTime {
  @patch
  static int _getCurrentMicros() => dates.currentTimeMicros();

  @patch
  static String _timeZoneNameForClampedSeconds(int secondsSinceEpoch) =>
      dates.timeZoneName(secondsSinceEpoch);

  @patch
  static int _timeZoneOffsetInSecondsForClampedSeconds(int secondsSinceEpoch) =>
      dates.timeZoneOffsetInSeconds(secondsSinceEpoch);
}

@patch
class Stopwatch {
  @patch
  static int _now() => Memory.clock();

  @patch
  static int _computeFrequency() => 1000000000;
}

@patch
class _WeakReference<T extends Object> {
  @runtime.WeakSlot()
  T? _storage;

  @patch
  T? get target => _storage;
  @patch
  set _target(T? value) => _storage = value;
}

@patch
class _WeakProperty {
  @runtime.EphemeronKey('_value')
  dynamic _key;
  dynamic _value;

  @patch
  get key => _key;
  @patch
  set key(k) => _key = k;
  @patch
  get value => _value;
  @patch
  set value(v) => _value = v;
}

@patch
class Type {
  @patch
  String toString() => metadata.TypeInfo.of(this).toString();
}

@patch
class NoSuchMethodError {
  // shortcut: signatures are not retained for VM mirrors, add them with reflective call metadata.
  @patch
  static String? _existingMethodSignature(
    Object? receiver,
    String methodName,
    int invocationType,
  ) => null;
}
