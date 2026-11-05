// ignore_for_file: annotate_overrides, use_primary_constructors
import 'effects.dart' as effects;

abstract class PrivateForwardContract {
  int _inherited([int value = 31]);
}

class PrivateForwardBase implements PrivateForwardContract {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(91);
    return invocation.positionalArguments[0];
  }
}

abstract class PrivateForwardMiddle extends PrivateForwardBase {
  int _inherited([int value = 43]);
}

Object? invokePrivateForward(PrivateForwardBase value, bool tearoff) {
  if (tearoff) {
    final tear = value._inherited;
    return tear();
  }
  return value._inherited();
}
