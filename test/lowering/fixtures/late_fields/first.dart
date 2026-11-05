import '../effects.dart';

class PrivateBase() {
  late int _value = tick(110);
  int readBase() => _value;
  int writeBase(int next) => _value = next;
}
