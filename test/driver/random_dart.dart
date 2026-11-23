import 'dart:math';

part 'random_expressions.dart';

enum Kind(final String name) {
  integer('int'),
  float('double'),
  boolean('bool'),

  /// Any object of the generated classes.
  object('C0'),

  /// A number of either kind, a number or null, and anything.
  number('num'),
  maybe('int?'),
  any('Object?');

  /// The kinds that the official runtime can print.
  static const List<Kind> plain = [integer, float, boolean];
}

typedef _Method = ({String name, Kind result, List<Kind> parameters});

/// Reproducible random functions in the Dart that is supported.
///
/// Every function takes constants for its arguments and terminates: each loop
/// counts its own variable down. Some operations throw, sometimes.
final class RandomDart(int seed) {
  final Random _random = Random(seed);
  final _lines = <String>[];
  final _functions =
      <({String name, Kind result, List<(String?, Kind)> parameters})>[];
  final _scopes = <List<(String, Kind)>>[];
  final _loops = <String?>[];
  final _methods = <_Method>[];
  late Kind _result;
  int _tries = 0;

  /// Whether to throw here, which is rarely done where nothing catches it.
  bool get _mayThrow => _chance(_tries > 0 ? 2 : 100);
  int _names = 0, _depth = 0;

  /// Bodies call only methods numbered below this, so that calls end.
  int _methodLimit = 0;

  /// Expressions calling each generated function, with their types.
  List<(String, Kind)> get calls => [
    for (final function in _functions)
      if (Kind.plain.contains(function.result))
        (_callOf(function, (kind) => _literal(kind)), function.result),
  ];

  String generate(int count) {
    _scopes.add([]);
    _globals();
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
    ('n0', Kind.number),
    ('a0', Kind.any),
  ];

  /// The fields that constructors take.
  static final _given = _fields.take(3).toList();
  static const _classCount = 8;

  /// Variables of the library and of a class, with and without constants to
  /// start with.
  void _globals() {
    void variables(String owner, String head, String prefix) {
      final kinds = [...Kind.values, ...Kind.values]..shuffle(_random);
      for (final (i, kind) in kinds.indexed) {
        final value = _random.nextBool()
            ? _literal(kind)
            : _expression(kind, 2);
        _line('$head${kind.name} $prefix$i = $value;');
        _scopes.first.add(('$owner$prefix$i', kind));
      }
    }

    variables('', '', 'g');
    _block('class S', () => variables('S.', 'static ', 's'));
  }

  /// A class K of constants that looks like C0.
  void _constants() {
    _block('class K implements C0', () {
      for (final (field, kind) in _fields) {
        _line('final ${kind.name} $field;');
        _line('set $field(${kind.name} value) {}');
      }
      _line('final K? k;');
      _line('C0? get o0 => k;');
      _line('set o0(C0? value) { }');
      _line('const K(this.i0, this.d0, this.b0, [this.k]) : n0 = d0, a0 = k;');
      _line('C0 operator +(C0 other) => b0 ? other : this;');
      _line('int operator [](int at) => i0 - at;');
      _line('void operator []=(int at, int value) {}');
      for (final (i, method) in _methods.indexed) {
        _method(method, i, isWhole: true, isRoot: false);
      }
    });
  }

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
    _constants();
  }

  void _class(String name, String relation, {required bool isWhole}) {
    _block('class $name$relation', () {
      if (isWhole) {
        for (final (field, kind) in _fields) {
          _line('${kind.name} $field;');
        }
        _line('C0? o0;');
        _line(
          '$name(this.i0, this.d0, [this.b0 = ${_literal(.boolean)}]) '
          ': n0 = i0, a0 = d0;',
        );
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
        if (_chance(4)) {
          _line('@override int get n0 => i0;');
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
      extra.add('${kind.name} $parameter = ${_constant(kind)}');
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

  /// An expression that is constant.
  String _constant(Kind kind) => switch (kind) {
    .object => 'const ${_constantObject()}',
    .any => _constant(_any(Kind.values.take(5).toList())),
    _ => _literal(kind),
  };

  String _constantObject() {
    final rest = _random.nextBool() ? ', ${_constantObject()}' : '';
    final values = [for (final (_, kind) in _given) _literal(kind)];
    return 'K(${values.join(', ')}$rest)';
  }

  String _literal(Kind kind) => switch (kind) {
    .object => _chance(3) ? _constant(kind) : _creation(_literal),
    .boolean => '${_random.nextBool()}',
    .number => _literal(_any([.integer, .float])),
    .maybe => _chance(3) ? '(null as int?)' : _literal(.integer),
    .any =>
      _chance(6)
          ? '(null as Object?)'
          : _literal(_any(Kind.values.take(6).toList())),
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

  /// The variables that are not final, as caught exceptions are.
  List<String> _assignable(Kind kind) => [
    for (final name in _variables(kind))
      if (!RegExp(r'^e\d+$').hasMatch(name)) name,
  ];

  void _declare(Kind kind) {
    final name = 'v${_names++}';
    final value = _expression(kind, 2);
    // Elsewhere, the type of the value may be another one.
    final isSafe = kind != .integer && kind != .boolean || !_chance(3);
    final head = isSafe ? kind.name : 'var';
    _line('$head $name = $value;');
    _scopes.last.add((name, kind));
  }

  void _statements(int count, int depth) {
    for (var i = 0; i < count; i++) {
      _statement(depth);
    }
  }

  void _statement(int depth) {
    switch (_random.nextInt(depth > 0 ? 22 : 9)) {
      case 0 || 1:
        _declare(_any(Kind.values));
      case 2:
        _unassigned();
      case 3 || 4 || 5:
        _line('${_assignment(_any(Kind.values), 2)};');
      case 6:
        final variable = _any(_assignable(.integer));
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
        _line('const ${kind.name} $name = ${_constant(kind)};');
        _line('${_any(_assignable(kind))} = $name;');
      case 18 || 19 || 20:
        _try(depth - 1);
      case 21 when _mayThrow:
        _line(
          'if (${_expression(.boolean, 2)}) throw ${_expression(.object, 1)};',
        );
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

  void _try(int depth) {
    _tries++;
    _block('try', () {
      _statements(1 + _random.nextInt(4), depth);
      if (_chance(3)) {
        _line('if (${_expression(.boolean, 2)}) throw ${_literal(.object)};');
      }
    });
    _tries--;
    final catches = _random.nextInt(3);
    for (var i = 0; i < catches; i++) {
      final class_ = _any([
        for (var i = 0; i < _classCount; i++) 'C$i',
        'K',
        'Error',
        'UnsupportedError',
        'Object',
      ]);
      final name = 'e${_names++}';
      final isObject = class_.startsWith(RegExp('[CK]'));
      _block('on $class_ catch ($name)', () {
        if (isObject) _scopes.last.add((name, .object));
        _statements(1 + _random.nextInt(2), depth);
        if (_chance(5)) _line('if (${_expression(.boolean, 1)}) rethrow;');
        // It is final, so nothing may assign it.
      });
    }
    final catchesAll = !_chance(4);
    if (catchesAll) _block('catch (_)', () => _statements(2, depth));
    if (catches == 0 && !catchesAll || _chance(3)) {
      _block('finally', () => _statements(1 + _random.nextInt(2), depth));
    }
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
}
