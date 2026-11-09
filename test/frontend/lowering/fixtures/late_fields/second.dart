import '../effects.dart';
import 'first.dart';

class PrivateChild() extends PrivateBase {
  late int _value = tick(111);
  int readChild() => _value;
  int writeChild(int next) => _value = next;
}

String privateFieldIdentity() {
  final child = PrivateChild();
  final first = child.readBase();
  final second = child.readChild();
  child.writeBase(tick(112));
  child.writeChild(tick(113));
  return '$first:$second:${child.readBase()}:${child.readChild()}';
}
