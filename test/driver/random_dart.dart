import 'dart:math';

enum Kind(final String name) {
  integer('int'),
  float('double'),
  boolean('bool'),
}

/// Reproducible random functions in the Dart that is supported.
///
/// Every function takes constants for its arguments, terminates and has no
/// operation that could throw: divisors and shifts are literals, and each loop
/// counts its own variable down.
final class RandomDart(int seed) {
  final Random _random = Random(seed);
  final _lines = <String>[];
  final _functions =
      <({String name, Kind result, List<(String?, Kind)> parameters})>[];
  final _scopes = <List<(String, Kind)>>[];
  final _loops = <String?>[];
  late Kind _result;
  int _names = 0, _depth = 0;

  /// Expressions calling each generated function, with their types.
  List<(String, Kind)> get calls => [
    for (final function in _functions)
      (_callOf(function, (kind) => _literal(kind)), function.result),
  ];

  String generate(int count) {
    for (var i = 0; i < count; i++) {
      _function('f$i');
    }
    return _lines.join('\n');
  }

  T _any<T>(List<T> values) => values[_random.nextInt(values.length)];
  bool _chance(int of) => _random.nextInt(of) == 0;

  void _line(String text) => _lines.add('${'  ' * _depth}$text');

  void _block(String head, void Function() body) {
    _line('$head {');
    _depth++;
    _scopes.add([]);
    body();
    _scopes.removeLast();
    _depth--;
    _line('}');
  }

  void _function(String name) {
    _result = _any(Kind.values);
    final positional = [
      for (var i = _random.nextInt(5); i > 0; i--) _any(Kind.values),
    ];
    final optional = [
      for (var i = _random.nextInt(3); i > 0; i--) _any(Kind.values),
    ];
    final isNamed = _random.nextBool();
    final parameters = <(String?, Kind)>[], texts = <String>[];
    final scope = <(String, Kind)>[];
    for (final kind in positional) {
      final parameter = 'p${_names++}';
      parameters.add((null, kind));
      texts.add('${kind.name} $parameter');
      scope.add((parameter, kind));
    }
    final extra = <String>[];
    for (final kind in optional) {
      final parameter = 'p${_names++}';
      parameters.add((isNamed ? parameter : null, kind));
      extra.add('${kind.name} $parameter = ${_literal(kind)}');
      scope.add((parameter, kind));
    }
    if (extra.isNotEmpty) {
      texts.add(isNamed ? '{${extra.join(', ')}}' : '[${extra.join(', ')}]');
    }
    _scopes.add(scope);
    _block('${_result.name} $name(${texts.join(', ')})', () {
      for (final kind in Kind.values) {
        _declare(kind);
      }
      _statements(3 + _random.nextInt(6), 3);
      _line('return ${_expression(_result, 3)};');
    });
    _scopes.removeLast();
    _functions.add((name: name, result: _result, parameters: parameters));
  }

  String _literal(Kind kind) => switch (kind) {
    .boolean => '${_random.nextBool()}',
    .integer => switch (_random.nextInt(4)) {
      0 => _any([
        '0',
        '1',
        '-1',
        '0x7fffffffffffffff',
        '-9223372036854775808',
        '9007199254740993',
      ]),
      1 => '${_random.nextInt(1 << 32) * _random.nextInt(1 << 31)}',
      _ => '${_random.nextInt(40) - 20}',
    },
    .float => switch (_random.nextInt(4)) {
      0 => _any([
        '0.0',
        '-0.0',
        '1e308',
        '5e-324',
        'double.infinity',
        'double.nan',
        '9007199254740992.0',
      ]),
      1 => '${_random.nextDouble() * 1000 - 500}',
      2 => '${_random.nextInt(9)}.0',
      _ => '${_random.nextInt(80) / 8 - 5}',
    },
  };

  List<String> _variables(Kind kind) => [
    for (final scope in _scopes)
      for (final (name, type) in scope)
        if (type == kind) name,
  ];

  void _declare(Kind kind) {
    final name = 'v${_names++}';
    final value = _expression(kind, 2);
    final head = _chance(3) ? 'var' : kind.name;
    // A bare int literal would make `var` an int.
    final isSafe = head == kind.name || kind != .float;
    _line('${isSafe ? head : kind.name} $name = $value;');
    _scopes.last.add((name, kind));
  }

  void _statements(int count, int depth) {
    for (var i = 0; i < count; i++) {
      _statement(depth);
    }
  }

  void _statement(int depth) {
    switch (_random.nextInt(depth > 0 ? 18 : 9)) {
      case 0 || 1:
        _declare(_any(Kind.values));
      case 2:
        _unassigned();
      case 3 || 4 || 5:
        _line('${_assignment(_any(Kind.values), 2)};');
      case 6:
        final variable = _any(_variables(.integer));
        _line('${_any(['$variable++', '--$variable', '$variable--'])};');
      case 7 when _loops.isNotEmpty:
        _leave();
      case 8 when _chance(3):
        _block('if (${_expression(.boolean, 2)})', () {
          _line('return ${_expression(_result, 2)};');
        });
      case 9 || 10:
        _if(depth - 1);
      case 11 || 12 || 13:
        _loop(depth - 1);
      case 14 || 15:
        _switch(depth - 1);
      case 16:
        final label = 'l${_names++}';
        _block('$label:', () {
          _statements(2, depth - 1);
          _line('if (${_expression(.boolean, 2)}) break $label;');
          _statements(2, depth - 1);
        });
      case 17:
        final name = 'c${_names++}', kind = _any(Kind.values);
        _line('const ${kind.name} $name = ${_literal(kind)};');
        _line('${_any(_variables(kind))} = $name;');
      default:
        _line('${_expression(_any(Kind.values), 2)};');
    }
  }

  /// A variable first assigned on both sides of a branch.
  void _unassigned() {
    final name = 'v${_names++}', kind = _any(Kind.values);
    _line('${kind.name} $name;');
    final first = _expression(kind, 2), second = _expression(kind, 2);
    _line(
      'if (${_expression(.boolean, 2)}) { $name = $first; } '
      'else { $name = $second; }',
    );
    _scopes.last.add((name, kind));
  }

  void _leave() {
    final label = _any(_loops);
    final target = label == null || _random.nextBool() ? '' : ' $label';
    final verb = _random.nextBool() ? 'break' : 'continue';
    // `break` inside a switch means the switch unless it names the loop.
    _line('if (${_expression(.boolean, 2)}) $verb$target;');
  }

  void _if(int depth) {
    _block('if (${_expression(.boolean, 3)})', () => _statements(2, depth));
    if (_random.nextBool()) _block('else', () => _statements(2, depth));
  }

  void _loop(int depth) {
    final counter = 'n${_names++}', limit = _random.nextInt(5);
    final label = _random.nextBool() ? 'l${_names++}' : null;
    final prefix = label == null ? '' : '$label: ';
    final condition = _random.nextBool()
        ? ''
        : ' && ${_expression(.boolean, 2)}';
    void body() {
      _loops.add(label);
      _statements(1 + _random.nextInt(4), depth);
      _loops.removeLast();
    }

    switch (_random.nextInt(3)) {
      case 0:
        _block(
          '${prefix}for (var $counter = $limit; $counter > 0$condition; $counter--)',
          body,
        );
      case 1:
        _line('var $counter = $limit;');
        _block('${prefix}while ($counter-- > 0$condition)', body);
      default:
        _line('var $counter = $limit;');
        _block('${prefix}do', body);
        _lines.add('${_lines.removeLast()} while (--$counter > 0$condition);');
    }
  }

  void _switch(int depth) {
    _block('switch (${_expression(.integer, 2)} % 4)', () {
      _depth++;
      for (final (i, value) in ([0, 1, 2, 3]..shuffle(_random)).indexed) {
        if (i == 3 && _random.nextBool()) break;
        _line('case $value:');
        // Without statements, a case shares those of the next one.
        if (_chance(4)) continue;
        _scopes.add([]);
        _statements(1 + _random.nextInt(2), depth);
        _line('${_assignment(.integer, 1)};');
        if (_chance(3)) _line('break;');
        _scopes.removeLast();
      }
      if (_random.nextBool()) {
        _line('default:');
        _line('${_assignment(.integer, 1)};');
      }
      _depth--;
    });
  }

  String _assignment(Kind kind, int depth) {
    final variable = _any(_variables(kind));
    if (_random.nextBool()) return '$variable = ${_expression(kind, depth)}';
    final (operator, right) = switch (kind) {
      .integer =>
        _chance(3)
            ? (
                _any(['~/', '%', '<<', '>>', '>>>']),
                '${1 + _random.nextInt(70)}',
              )
            : (
                _any(['+', '-', '*', '&', '|', '^']),
                _expression(.integer, depth),
              ),
      .float => (
        _any(['+', '-', '*', '/', '%']),
        _expression(_any([.integer, .float]), depth),
      ),
      .boolean => (_any(['&', '|', '^']), _expression(.boolean, depth)),
    };
    return '$variable $operator= $right';
  }

  String _expression(Kind kind, int depth) {
    if (depth == 0 || _chance(6)) {
      final variables = _variables(kind);
      return variables.isEmpty || _chance(3)
          ? '(${_literal(kind)})'
          : _any(variables);
    }
    String inner(Kind kind) => _expression(kind, depth - 1);
    switch (_random.nextInt(9)) {
      case 0:
        return '(${inner(.boolean)} ? ${inner(kind)} : ${inner(kind)})';
      case 1 when _variables(kind).isNotEmpty:
        return '(${_assignment(kind, depth - 1)})';
      case 2:
        final matching = _functions.where((f) => f.result == kind).toList();
        // Calls are kept outside loops, so programs stay small.
        if (matching.isNotEmpty && _loops.isEmpty) {
          return _callOf(_any(matching), (kind) => _expression(kind, 1));
        }
    }
    return switch (kind) {
      .integer => _integer(inner),
      .float => _float(inner),
      .boolean => _boolean(inner),
    };
  }

  String _integer(String Function(Kind) inner) {
    switch (_random.nextInt(8)) {
      case 0:
        return '(${_any(['-', '~'])}(${inner(.integer)}))';
      case 1:
        final operator = _any(['~/', '%', '<<', '>>', '>>>']);
        final right = operator == '~/' || operator == '%'
            ? _any([
                '1',
                '2',
                '3',
                '7',
                '(-1)',
                '(-5)',
                '1000003',
                '(-9223372036854775808)',
              ])
            : '${_random.nextInt(70)}';
        return '(${inner(.integer)} $operator $right)';
      case 2 when _variables(.integer).isNotEmpty:
        final variable = _any(_variables(.integer));
        return '(${_any(['$variable++', '++$variable', '$variable--'])})';
      default:
        final operator = _any(['+', '-', '*', '&', '|', '^']);
        return '(${inner(.integer)} $operator ${inner(.integer)})';
    }
  }

  String _float(String Function(Kind) inner) {
    if (_chance(6)) return '(-(${inner(.float)}))';
    if (_chance(6)) return '(${inner(.integer)} / ${inner(.integer)})';
    final operator = _any(['+', '-', '*', '/', '%']);
    // One side may be an int, which is converted.
    final (left, right) = _any<(Kind, Kind)>([
      (.float, .float),
      (.float, .integer),
      (.integer, .float),
    ]);
    return '(${inner(left)} $operator ${inner(right)})';
  }

  String _boolean(String Function(Kind) inner) {
    switch (_random.nextInt(6)) {
      case 0:
        return '(!${inner(.boolean)})';
      case 1 || 2:
        final operator = _any(['&&', '||', '&', '|', '^', '==', '!=']);
        return '(${inner(.boolean)} $operator ${inner(.boolean)})';
      default:
        final operator = _any(['<', '<=', '>', '>=', '==', '!=']);
        final left = _any<Kind>([.integer, .float]);
        final right = _any<Kind>([.integer, .float]);
        return '(${inner(left)} $operator ${inner(right)})';
    }
  }

  String _callOf(
    ({String name, Kind result, List<(String?, Kind)> parameters}) function,
    String Function(Kind kind) argument,
  ) {
    final positional = <String>[], named = <String>[];
    for (final (name, kind) in function.parameters) {
      if (name == null) {
        positional.add(argument(kind));
      } else if (_random.nextBool()) {
        named.add('$name: ${argument(kind)}');
      }
    }
    return '${function.name}(${[...positional, ...named..shuffle(_random)].join(', ')})';
  }
}
