import '../effects.dart';

int _private = tick(205);
int readPrivate() => _private;

class SharedName() {
  static int value = tick(206);
}
