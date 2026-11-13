import 'dart:ffi';

void main() {
  final callback = NativeCallable<Void Function()>.isolateLocal(() {});
  if (!callback.keepIsolateAlive) throw StateError('default lifetime');
  print('ready');
}
