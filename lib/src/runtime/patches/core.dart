import 'dart:ffi' as ffi;

import '../contracts.dart' as runtime;

@patch
class WeakReference<T extends Object> {
  factory WeakReference(T target) => _WeakReference<T>(target);
}

final class _WeakReference<T extends Object>(T value)
    implements WeakReference<T> {
  @runtime.WeakSlot()
  T? _target = value;

  @override
  T? get target => _target;

  this {
    if (value is num ||
        value is String ||
        value is bool ||
        value is Record ||
        value is ffi.Pointer ||
        value is ffi.Struct ||
        value is ffi.Union) {
      throw ArgumentError.value(
        value,
        'target',
        'Invalid weak reference target',
      );
    }
  }
}
