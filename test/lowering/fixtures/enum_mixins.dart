mixin Label on Enum {
  String label() => '$index:$name';
  @override
  String toString() => 'mixed:$index';
}

enum const Labeled() with Label {
  a,
  b,
}

mixin Generic<T> {
  T echo(T value) => value;
  T Function(T) get identity => echo;
}

enum const Numbered() with Generic<int> {
  a,
}

enum const Parameterized<T>(final T value) with Generic<T> {
  number<int>(3),
  text<String>('four'),
}

String labels() =>
    '${Labeled.a.label()}:${Labeled.b}:${Labeled.a.toString()}:${Numbered.a}:${Numbered.a.echo(2)}';

String parameters() {
  final value = Parameterized.number;
  final Object erased = value;
  return '${value.identity(5)}:${Parameterized.text.echo('six')}:${erased is Generic<int>}:${identical(value, Parameterized.number)}';
}
