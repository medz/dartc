import 'dart:math';

enum Kind(final String name) {
  integer('int'),
  float('double'),
  boolean('bool'),

  /// Any object of the generated classes.
  object('C0');

  /// The kinds that the official runtime can print.
  static const List<Kind> plain = [integer, float, boolean];
}

typedef _Method = ({String name, Kind result, List<Kind> parameters});

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
  final _methods = <_Method>[];
  late Kind _result;
  int _names = 0, _depth = 0;

  /// Bodies call only methods numbered below this, so that calls end.
  int _methodLimit = 0;

  /// Expressions calling each generated function, with their types.
  List<(String, Kind)> get calls => [
    for (final function in _functions)
      if (function.result != .object)
        (_callOf(function, (kind) => _literal(kind)), function.result),
  ];

  String generate(int count) {
    _classes();
    _methodLimit = _methods.length;
    for (var i = 0; i < count; i++) {
      _function('f$i');
    }
    return _lines.join('\n');
  }

  static const _fields = [
    ('i0', Kind.integer),
    ('d0', Kind.float),
    ('b0', Kind.boolean),
  ];
  static const _classCount = 8;

  /// A class C0 and others that extend or implement it.
  void _classes() {
    for (var i = 0; i < 6; i++) {
      _methods.add((
        name: 'm$i',
        result: _any(Kind.values),
        parameters: [
          for (var j = _random.nextInt(4); j > 0; j--) _any(Kind.values),
        ],
      ));
    }
    for (var i = 0; i < _classCount; i++) {
      final isAlone = i > 0 && _chance(5);
      final parent = i == 0 ? null : _random.nextInt(i);
      final relation = i == 0
          ? ''
          : isAlone
          ? ' implements C0'
          : ' extends C$parent';
      _class('C$i', relation, isWhole: i == 0 || isAlone);
    }
  }

  void _class(String name, String relation, {required bool isWhole}) {
    _block('class $name$relation', () {
      if (isWhole) {
        for (final (field, kind) in _fields) {
          _line('${kind.name} $field;');
        }
        _line('C0? o0;');
        _line('$name(this.i0, this.d0, [this.b0 = ${_literal(.boolean)}]);');
        _line('C0 operator +(C0 other) => b0 ? this : other;');
        _line('int operator [](int at) => i0 + at;');
        _line('void operator []=(int at, int value) => i0 = at ^ value;');
      } else {
        switch (_random.nextInt(3)) {
          case 0:
            _line('$name(super.i0, super.d0, [super.b0]);');
          case 1:
            _line(
              '$name(int i, double d, [bool b = true]) : super(i + 1, d, b) '
              "{ print('$name'); i0 *= 2; }",
            );
          default:
            _line('int extra = ${_literal(.integer)};');
            _line(
              '$name(int i, double d, [bool b = false]) : super(i, d / 2, b) '
              '{ i0 += extra; }',
            );
        }
        if (_chance(4)) {
          _line('@override int get i0 => super.i0 + 1;');
        }
        if (_chance(4)) {
          _line('@override set d0(double value) => super.d0 = value * 2;');
        }
        if (_chance(4)) {
          _line(
            '@override bool operator ==(Object other) '
            '=> b0 || super == other;',
          );
        }
        if (_chance(4)) {
          _line('@override int operator [](int at) => super[at] * 3;');
        }
      }
      for (final (i, method) in _methods.indexed) {
        if (isWhole || _chance(2)) {
          _method(method, i, isWhole: isWhole, isRoot: relation.isEmpty);
        }
      }
    });
  }

  void _method(
    _Method method,
    int number, {
    required bool isWhole,
    required bool isRoot,
  }) {
    _result = method.result;
    _methodLimit = number;
    final names = [for (final _ in method.parameters) 'p${_names++}'];
    final texts = [
      for (final (i, kind) in method.parameters.indexed)
        '${kind.name} ${names[i]}',
      // Subclasses take more than C0, each with its own default.
      if (!isRoot && number.isEven) '[int q = ${_random.nextInt(9)}]',
    ];
    _scopes.add([
      ..._fields,
      for (final (i, kind) in method.parameters.indexed) (names[i], kind),
      if (!isRoot && number.isEven) ('q', .integer),
    ]);
    _block('${_result.name} ${method.name}(${texts.join(', ')})', () {
      _line('C0 self${_names++} = this;');
      _scopes.last.add(('self${_names - 1}', .object));
      _statements(1 + _random.nextInt(3), 1);
      if (!isWhole && _random.nextBool()) {
        final arguments = method.parameters.map((kind) => _expression(kind, 1));
        final name = 'v${_names++}';
        _line(
          '${_result.name} $name = '
          'super.${method.name}(${arguments.join(', ')});',
        );
        _scopes.last.add((name, _result));
      }
      _line('return ${_expression(_result, 2)};');
    });
    _scopes.removeLast();
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
      for (var i = _random.nextInt(3); i > 0; i--) _any(Kind.plain),
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

  String _creation(String Function(Kind kind) argument) {
    final rest = _random.nextBool() ? ', ${argument(.boolean)}' : '';
    final class_ = 'C${_random.nextInt(_classCount)}';
    return '$class_(${argument(.integer)}, ${argument(.float)}$rest)';
  }

  String _literal(Kind kind) => switch (kind) {
    .object => _creation(_literal),
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
        if (type == kind)
          name
        else if (type == .object)
          for (final (field, fieldKind) in _fields)
            if (fieldKind == kind) '$name.$field',
  ];

  void _declare(Kind kind) {
    final name = 'v${_names++}';
    final value = _expression(kind, 2);
    final head = kind != .object && _chance(3) ? 'var' : kind.name;
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
        final name = 'c${_names++}', kind = _any(Kind.plain);
        _line('const ${kind.name} $name = ${_literal(kind)};');
        _line('${_any(_variables(kind))} = $name;');
      case 8:
        _line("print('trace ${_names++} é');");
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
      .object => ('+', _expression(.object, depth)),
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
    switch (_random.nextInt(11)) {
      // Methods call less, or the work would grow with every level.
      case 9 || 10
          when _loops.isEmpty &&
              _variables(.object).isNotEmpty &&
              (_methodLimit == _methods.length || _chance(5)):
        final callable = [
          for (final method in _methods.take(_methodLimit))
            if (method.result == kind) method,
        ];
        if (callable.isNotEmpty) {
          final method = _any(callable);
          final arguments = method.parameters.map((k) => _expression(k, 1));
          return '${_any(_variables(.object))}'
              '.${method.name}(${arguments.join(', ')})';
        }
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
      .object => _object(inner),
    };
  }

  String _object(String Function(Kind) inner) {
    final variables = _variables(.object);
    if (variables.isEmpty || _chance(3)) return _creation(inner);
    final variable = _any(variables);
    return switch (_random.nextInt(4)) {
      0 => '(${inner(.object)} + ${inner(.object)})',
      1 => '($variable.o0 ?? ${inner(.object)})',
      2 => '($variable.o0 ??= ${inner(.object)})',
      _ => variable,
    };
  }

  String _integer(String Function(Kind) inner) {
    switch (_random.nextInt(9)) {
      case 8 when _variables(.object).isNotEmpty:
        final variable = _any(_variables(.object));
        return _any([
          '$variable[${inner(.integer)}]',
          '($variable[${inner(.integer)}] = ${inner(.integer)})',
          '($variable[${inner(.integer)}] += ${inner(.integer)})',
        ]);
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
    switch (_random.nextInt(8)) {
      case 6 when _variables(.object).isNotEmpty:
        final variable = _any(_variables(.object));
        return _any([
          '($variable == ${inner(.object)})',
          '(${inner(.object)} != $variable)',
          'identical($variable, ${inner(.object)})',
          '($variable.o0 == null)',
          '($variable.o0 != ${inner(.object)})',
        ]);
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
