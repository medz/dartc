import '../effects.dart';
part 'first_part.dart';

int shared = tick(201);
int _private = tick(202);
int readPrivate() => _private;
int updatePrivate() => ++_private;

class SharedName() {
  static int value = tick(203);
}
