import 'dart:ffi';

void main() {
  final callback = NativeCallable<Void Function()>.isolateLocal(() {});
  callback.keepIsolateAlive = false;
  callback.keepIsolateAlive = true;
  callback.keepIsolateAlive = false;
  print('idle');
}
