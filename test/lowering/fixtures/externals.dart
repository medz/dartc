external int sum(int left, [int right = 2]);
external T identity<T extends num>(T value);
external int setting;

class Api {
  external new(int value);
  external factory named({int value = 1});
  external int value;
  external int call(int x, {int y = 3});
  external static int create(int x);
}

extension Extra on int {
  external int plus([int value = 1]);
}

int use() => identity(4);
