// Functions of C that are called when objects are gone, or the program ends.
import 'dart:_heap/objects.dart' show usesNativeFinalizers;
import 'dart:_internal' show FinalizerBase, FinalizerEntry;

@patch
final class _NativeFinalizer {
  @patch
  late Pointer<NativeFinalizerFunction> _callback;

  @patch
  _NativeFinalizer(Pointer<NativeFinalizerFunction> callback) {
    usesNativeFinalizers();
    _posted;
    allEntries = <FinalizerEntry>{};
    _callback = callback;
    setIsolate();
    isolateRegisterFinalizer();
  }

  @patch
  void attach(
    Object value,
    Pointer<Void> token, {
    Object? detach,
    int? externalSize,
  }) {
    externalSize ??= 0;
    RangeError.checkNotNegative(externalSize, 'externalSize');
    if (detach != null) checkValidWeakTarget(detach, 'detach');
    _attach(value, _callback, token, detach, externalSize);
  }

  void _attach(
    Object value,
    Pointer<NativeFinalizerFunction> callback,
    Pointer<Void> token,
    Object? detach,
    int externalSize,
  ) {
    final entry = FinalizerEntry.allocate(value, token, detach, this)
      ..function = callback._address
      ..argument = token._address;
    allEntries.add(entry);
    if (externalSize > 0) entry.setExternalSize(externalSize);
    if (detach != null) (detachments[detach] ??= <FinalizerEntry>{}).add(entry);
  }

  void handleCollected() => _removeEntries();
}

final _NativeFinalizer _listFinalizer = _NativeFinalizer(nullptr);

@patch
void _attachAsTypedListFinalizer(
  Pointer<NativeFinalizerFunction> callback,
  Object typedList,
  Pointer pointer,
  int? externalSize,
) => _listFinalizer._attach(
  typedList,
  callback,
  pointer.cast(),
  null,
  externalSize ?? 0,
);

/// Calls the function of [entry] at the end, if that has not been done.
void _finalize(FinalizerEntry entry) {
  final function = entry.function;
  if (function == 0) return;
  entry.function = 0;
  final callback = Pointer<NativeFinalizerFunction>.fromAddress(function);
  callback.asFunction<void Function(Pointer<Void>)>()(
    Pointer.fromAddress(entry.argument),
  );
}
