import 'dart:math';

/// Reproducible random programs that match random values with random patterns.
final class RandomPatterns(int seed) {
  final Random _random = Random(seed);
  int _names = 0;

  /// The variables that the pattern made now declares.
  final _variables = <String>[];

  T _any<T>(List<T> choices) => choices[_random.nextInt(choices.length)];
  bool _chance(int of) => _random.nextInt(of) == 0;

  static const _declarations = r'''
enum E { a, b, c; E get next => values[(index + 1) % 3]; }
class P {
  final Object? x, y;
  const P(this.x, [this.y]);
  Object? get seen { print('seen $x'); return x; }
  Object? same(Object? z) => z;
  String toString() => 'P($x, $y)';
}
class Q<T> extends P { const Q(T super.x); T get value => x as T; }
class L extends P { final List<int> items; L(this.items) : super(items.length); }
extension on P { Object? get swapped => y; }
extension Ints on int { int get half => this ~/ 2; bool get isSmall => this < 3; }
extension type const Id(int n) { int get next => n + 1; }
Object? first(Object? Function() f) { try { return f(); } catch (e) { return '! ${e.runtimeType}'; } }
''';

  /// A constant that a pattern can be.
  String get _constant => _any(const [
    '0', '1', '2', '-1', 'true', 'false', 'null', "'a'", "'b'", "''", //
    'E.a', 'E.b', '1.5', 'const P(1)', 'const P(1, 2)', 'const (1, 2)',
    'const [1, 2]',
  ]);

  String _value([int depth = 3]) {
    if (depth == 0 || _chance(3)) return _any([_constant, '3', '7', 'E.c']);
    String inner() => _value(depth - 1);
    String some(int least) =>
        [for (var i = least + _random.nextInt(4 - least); i > 0; i--) inner()]
            .join(', ');
    return switch (_random.nextInt(11)) {
      0 || 1 => '<Object?>[${some(0)}]',
      2 =>
        '<int>[${[for (var i = _random.nextInt(4); i > 0; i--) _random.nextInt(4)].join(', ')}]',
      3 =>
        "<Object?, Object?>{'a': ${inner()}${_chance(2) ? ", 'b': ${inner()}" : ''}}",
      4 || 5 => '(${inner()}, ${inner()})',
      6 => '(${inner()}, n: ${inner()})',
      7 => 'P(${inner()}, ${inner()})',
      8 => 'Q<${_any(const ['int', 'Object?'])}>(${_random.nextInt(3)})',
      9 => 'L([${_random.nextInt(3)}, ${_random.nextInt(3)}])',
      _ => '(x: ${inner()}, n: ${inner()})',
    };
  }

  /// A pattern for any value, which declares variables if it [binds].
  String _pattern(int depth, {required bool binds}) {
    if (depth == 0 || _chance(5)) return _leaf(binds);
    String inner() => _pattern(depth - 1, binds: binds);
    switch (_random.nextInt(12)) {
      case 0:
        final parts = [for (var i = _random.nextInt(4); i > 0; i--) inner()];
        if (_chance(2)) {
          final rest = _chance(2) ? '' : _restPattern(depth, binds);
          parts.insert(_random.nextInt(parts.length + 1), '...$rest');
        }
        return '[${parts.join(', ')}]';
      case 1:
        return "{'a': ${inner()}${_chance(2) ? ", 'b': ${inner()}" : ''}}";
      case 2 || 3:
        return '(${inner()}, ${inner()})';
      case 4:
        return _chance(2)
            ? '(${inner()}, n: ${inner()})'
            : '(n: ${inner()}, x: ${inner()})';
      case 5 || 6:
        final fields = [
          for (final name in ['x', 'seen', 'swapped', 'y'])
            if (_chance(3)) '$name: ${inner()}',
        ];
        return 'P(${fields.join(', ')})';
      case 7:
        return '${inner()} && ${inner()}'.replaceFirstMapped(
          RegExp('^(.*)\$', dotAll: true),
          (m) => '(${m[0]})',
        );
      case 8:
        final bare = [
          for (var i = 0; i < 2; i++) _pattern(depth - 1, binds: false),
        ];
        return '(${bare.join(' || ')})';
      case 9:
        return '(${inner()})?';
      case 10:
        return 'Q<int>(value: ${_chance(2) ? _number(binds) : inner()})';
      default:
        return 'L(items: [${_number(binds)}, ...], x: int(half: ${_number(binds)}))';
    }
  }

  String _restPattern(int depth, bool binds) => binds && _chance(2)
      ? 'var ${_declare()}'
      : _any(const ['[]', '[_]', '[_, ...]', '_']);

  String _declare() {
    final name = 'v${_names++}';
    _variables.add(name);
    return name;
  }

  /// A pattern for an `int`.
  String _number(bool binds) => switch (_random.nextInt(5)) {
    0 => '> ${_random.nextInt(3)}',
    1 => '${_random.nextInt(3)}',
    2 when binds => 'var ${_declare()}',
    3 => '(>= 0 && < ${_random.nextInt(4)})',
    4 => 'int(isSmall: ${_random.nextBool()}, half: _)',
    _ => '_',
  };

  String _leaf(bool binds) => switch (_random.nextInt(9)) {
    0 || 1 when binds => 'var ${_declare()}',
    2 when binds => 'int ${_declare()}',
    3 => _any(const [
      'int _',
      'String _',
      'List<int> _',
      'P _',
      'E()',
      'num()',
    ]),
    4 => 'int(sign: ${_number(binds)})',
    5 => 'E(next: ${_any(const ['E.a', 'E.b', '_'])})',
    6 => '_',
    _ => _constant,
  };

  String _guard() => _variables.isEmpty || !_chance(3)
      ? ''
      : ' when ${_any([for (final v in _variables) '$v is int', for (final v in _variables) '$v != null'])}';

  String _shown() => ['', ..._variables].join(r' $').trimLeft();

  String _case(int depth) {
    _variables.clear();
    return _pattern(depth, binds: true);
  }

  String _expression(int index) {
    final cases = [
      for (var i = 2 + _random.nextInt(4); i > 0; i--)
        () {
          final pattern = _case(3);
          return "    $pattern${_guard()} => '$i ${_shown()}',\n";
        }(),
    ];
    return 'String match$index(Object? o) => switch (o) {\n'
        "${cases.join()}    _ => 'none',\n  };\n";
  }

  String _statement(int index) {
    final lines = [
      for (var i = 2 + _random.nextInt(4); i > 0; i--)
        () {
          if (_chance(3)) {
            final both = [
              for (var i = 0; i < 2; i++) _pattern(2, binds: false),
            ];
            return '    case ${both[0]}:\n    case ${both[1]}:\n'
                "      return '$i both';\n";
          }
          final pattern = _case(3);
          return "    case $pattern${_guard()}:\n      return '$i ${_shown()}';\n";
        }(),
    ];
    final pattern = _case(2);
    final test = "  if (o case $pattern${_guard()}) print('if ${_shown()}');\n";
    return 'String match$index(Object? o) {\n$test  switch (o) {\n'
        "${lines.join()}    default:\n      return 'none';\n  }\n}\n";
  }

  /// A whole program.
  String generate() {
    final functions = [
      for (var i = 0; i < 8; i++) i.isEven ? _expression(i) : _statement(i),
    ];
    final values = [for (var i = 0; i < 40; i++) _value()];
    return '$_declarations${functions.join()}'
        'void main() {\n'
        '  final values = <Object? Function()>[\n'
        '${[for (final value in values) '    () => $value,\n'].join()}  ];\n'
        '  for (final make in values) {\n'
        '    final value = make();\n'
        r"    print('$value ${first(() => value == make())}');"
        '\n'
        '${[for (var i = 0; i < 8; i++) '    print(first(() => match$i(value)));\n'].join()}'
        '  }\n}\n';
  }
}
