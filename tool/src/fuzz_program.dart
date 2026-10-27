enum _Type { integer, boolean }

const _integers = <String>[
  '0',
  '1',
  '-1',
  '9223372036854775807',
  '-9223372036854775808',
  '4611686018427387903',
  '4611686018427387904',
  '-4611686018427387905',
  '2147483647',
  '-2147483648',
  '4294967295',
  '4294967296',
];
const _counts = <String>['0', '1', '31', '32', '62', '63', '64', '65', '127'];
const _arithmetic = <String>['+', '-', '*', '&', '|', '^'];
const _comparisons = <String>['==', '!=', '<', '<=', '>', '>='];
const _shifts = <String>['<<', '>>', '>>>'];

class GeneratedProgram {
  final int seed;
  final List<_Statement> _statements;

  GeneratedProgram._(this.seed, this._statements);

  String get source {
    final result = StringBuffer(r'''
int trace = 0;
void note(int tag) { trace = (trace * 33 + tag) % 1000000007; }
int tapInt(int tag, int value) { note(tag); return value; }
bool tapBool(int tag, bool value) { note(tag); return value; }
int combine(int left, int right) { note(29); return (left ^ right) + right; }
bool decide(bool left, bool right) { note(30); return left != right; }
int shiftLeft(int value, int count) => value << count;
int shiftRight(int value, int count) => value >> count;
int shiftUnsigned(int value, int count) => value >>> count;
void main() {
  int value = 0;
  bool flag = false;
''');
    for (final statement in _statements) {
      statement.write(result, '  ', 0);
    }
    result.write("  print('end:\$value:\$flag:\$trace');\n}\n");
    return result.toString();
  }

  Map<String, Object?> toJson() => {
    'version': 2,
    'seed': seed,
    'statements': [for (final statement in _statements) statement.toJson()],
  };

  Iterable<GeneratedProgram> reductions() sync* {
    for (var i = 0; i < _statements.length; i++) {
      yield GeneratedProgram._(seed, _without(_statements, i));
    }
    for (var i = 0; i < _statements.length; i++) {
      for (final smaller in _statements[i].reductions()) {
        yield GeneratedProgram._(seed, _replace(_statements, i, smaller));
      }
    }
  }
}

GeneratedProgram programFromJson(Map<String, Object?> model) {
  if (_integer(model['version']) != 2)
    throw const FormatException('Unknown program model');
  final seed = _integer(model['seed']);
  if (seed < 0 || seed > 0xffffffff) {
    throw const FormatException('Program seed must be unsigned 32-bit');
  }
  final ids = <int>{};
  return GeneratedProgram._(seed, [
    for (final value in _list(model['statements']))
      _statementFromJson(value, ids),
  ]);
}

GeneratedProgram generateProgram(int seed) {
  seed &= 0xffffffff;
  final random = _Random(seed);
  var id = 0;
  _Statement statement(
    String op,
    _Expression? expression, {
    List<_Statement> body = const [],
    List<_Statement> otherwise = const [],
    int bound = 0,
  }) => _Statement(
    id++,
    op,
    expression,
    body: body,
    otherwise: otherwise,
    bound: bound,
  );
  final statements = <_Statement>[
    statement('value', _tap(1, _int(_integers[seed % _integers.length]))),
    statement(
      'flag',
      _operation('||', [
        _operation('&&', [
          _tap(2, _bool(random.next(2) == 0)),
          _tap(3, _bool(random.next(2) == 0)),
        ]),
        _operation('!', [_tap(4, _bool(random.next(2) == 0))]),
      ]),
    ),
    // Both operands cross real call boundaries; a large count cannot be folded.
    statement(
      'value',
      _operation('shiftUnsigned', [
        _tap(5, _int('-1')),
        _tap(6, _int((64 + seed % 2).toString())),
      ]),
    ),
    statement(
      'value',
      _operation(_shifts[random.next(_shifts.length)], [
        _operation('value'),
        _tap(7, _int(_counts[seed % _counts.length])),
      ]),
    ),
    statement(
      'if',
      _boolean(random, 2),
      body: [statement('value', _integerExpression(random, 2))],
      otherwise: [statement('value', _integerExpression(random, 2))],
    ),
    statement(
      'loop',
      null,
      bound: 1 + random.next(3),
      body: [
        statement(
          'value',
          _operation('combine', [
            _operation('value'),
            _integerExpression(random, 1),
          ]),
        ),
        statement('flag', _boolean(random, 2)),
      ],
    ),
    statement(
      'value',
      _operation('choose', [
        _boolean(random, 2),
        _integerExpression(random, 2),
        _integerExpression(random, 2),
      ]),
    ),
  ];
  return GeneratedProgram._(seed, statements);
}

class _Random {
  int state;
  _Random(this.state);
  int next(int limit) {
    state = (state * 1664525 + 1013904223) & 0xffffffff;
    return state % limit;
  }
}

_Expression _int(String value) => _operation('int', const [], value);
_Expression _bool(bool value) => _operation('bool', const [], value.toString());
_Expression _tap(int tag, _Expression value) =>
    _operation('tap', [value], '', tag);

_Expression _integerExpression(_Random random, int depth) {
  if (depth == 0) {
    if (random.next(3) == 0) return _operation('value');
    return _int(_integers[random.next(_integers.length)]);
  }
  switch (random.next(7)) {
    case 0:
      return _operation(random.next(2) == 0 ? 'negate' : '~', [
        _integerExpression(random, depth - 1),
      ]);
    case 1:
      return _operation(_arithmetic[random.next(_arithmetic.length)], [
        _integerExpression(random, depth - 1),
        _integerExpression(random, depth - 1),
      ]);
    case 2:
      return _operation(_shifts[random.next(_shifts.length)], [
        _integerExpression(random, depth - 1),
        _tap(8 + random.next(20), _int(_counts[random.next(_counts.length)])),
      ]);
    case 3:
      return _operation('choose', [
        _boolean(random, depth - 1),
        _integerExpression(random, depth - 1),
        _integerExpression(random, depth - 1),
      ]);
    case 4:
      return _operation('combine', [
        _integerExpression(random, depth - 1),
        _integerExpression(random, depth - 1),
      ]);
    default:
      return _tap(8 + random.next(20), _integerExpression(random, depth - 1));
  }
}

_Expression _boolean(_Random random, int depth) {
  if (depth == 0) {
    if (random.next(3) == 0) return _operation('flag');
    return _tap(8 + random.next(20), _bool(random.next(2) == 0));
  }
  switch (random.next(5)) {
    case 0:
      return _operation('!', [_boolean(random, depth - 1)]);
    case 1:
      return _operation(random.next(2) == 0 ? '&&' : '||', [
        _boolean(random, depth - 1),
        _boolean(random, depth - 1),
      ]);
    case 2:
      return _operation(_comparisons[random.next(_comparisons.length)], [
        _integerExpression(random, depth - 1),
        _integerExpression(random, depth - 1),
      ]);
    case 3:
      return _operation('decide', [
        _boolean(random, depth - 1),
        _boolean(random, depth - 1),
      ]);
    default:
      return _tap(8 + random.next(20), _boolean(random, depth - 1));
  }
}

class _Expression {
  final _Type type;
  final String op;
  final String value;
  final int tag;
  final List<_Expression> args;
  _Expression(this.type, this.op, this.value, this.tag, this.args);

  String get source {
    if (op == 'int' || op == 'bool') return value;
    if (op == 'value' || op == 'flag') return op;
    if (op == 'tap') {
      final name = type == _Type.integer ? 'tapInt' : 'tapBool';
      return '$name($tag, ${args[0].source})';
    }
    if (op == 'combine' || op == 'decide' || op.startsWith('shift')) {
      return '$op(${args[0].source}, ${args[1].source})';
    }
    if (op == 'choose')
      return '(${args[0].source} ? ${args[1].source} : ${args[2].source})';
    if (args.length == 1)
      return '(${op == 'negate' ? '-' : op}(${args[0].source}))';
    return '(${args[0].source} $op ${args[1].source})';
  }

  Map<String, Object?> toJson() => {
    'type': type == _Type.integer ? 'int' : 'bool',
    'op': op,
    if (op == 'int' || op == 'bool') 'value': value,
    if (op == 'tap') 'tag': tag,
    'args': [for (final argument in args) argument.toJson()],
  };

  Iterable<_Expression> reductions() sync* {
    if (op == 'int') {
      final number = int.parse(value);
      if (number != 0) yield _int('0');
      if (number > 1 || number < -1) {
        final unit = number < 0 ? -1 : 1;
        yield _int(unit.toString());
        final half = number ~/ 2;
        if (half != unit) yield _int(half.toString());
      }
      return;
    }
    if (op == 'bool') {
      if (value == 'true') yield _bool(false);
      return;
    }
    yield type == _Type.integer ? _int('0') : _bool(false);
    for (final argument in args) {
      if (argument.type == type) yield argument;
    }
    for (var i = 0; i < args.length; i++) {
      for (final smaller in args[i].reductions()) {
        yield _operation(op, _replace(args, i, smaller), value, tag);
      }
    }
  }
}

_Expression _operation(
  String op, [
  List<_Expression> args = const [],
  String value = '',
  int tag = 0,
]) {
  _Type type;
  var count = 0;
  if (op == 'int') {
    final number = int.tryParse(value);
    if (number == null || number.toString() != value)
      throw const FormatException('Invalid int64 literal');
    type = _Type.integer;
  } else if (op == 'bool') {
    if (value != 'true' && value != 'false')
      throw const FormatException('Invalid bool literal');
    type = _Type.boolean;
  } else if (op == 'value' || op == 'flag') {
    type = op == 'value' ? _Type.integer : _Type.boolean;
  } else if (op == 'tap') {
    count = 1;
    if (tag < 1 || tag > 31 || args.length != count)
      throw const FormatException('Invalid tap');
    type = args[0].type;
  } else if (op == 'choose') {
    count = 3;
    if (args.length != count ||
        args[0].type != _Type.boolean ||
        args[1].type != args[2].type)
      throw const FormatException('Invalid conditional');
    type = args[1].type;
  } else if (op == 'negate' || op == '~' || op == '!') {
    count = 1;
    type = op == '!' ? _Type.boolean : _Type.integer;
    if (args.length != count || args[0].type != type)
      throw const FormatException('Invalid unary operand');
  } else {
    count = 2;
    if (args.length != count || args[0].type != args[1].type)
      throw const FormatException('Invalid binary operands');
    type = args[0].type;
    if (_comparisons.contains(op)) {
      if (op != '==' && op != '!=' && type != _Type.integer)
        throw const FormatException('Invalid comparison');
      type = _Type.boolean;
    } else if (op == '&&' || op == '||' || op == 'decide') {
      if (type != _Type.boolean)
        throw const FormatException('Expected bool operands');
    } else if (_arithmetic.contains(op) ||
        _shifts.contains(op) ||
        op == 'combine' ||
        op == 'shiftLeft' ||
        op == 'shiftRight' ||
        op == 'shiftUnsigned') {
      if (type != _Type.integer)
        throw const FormatException('Expected int operands');
    } else {
      throw FormatException('Unknown expression $op');
    }
  }
  if (args.length != count)
    throw const FormatException('Invalid expression arity');
  return _Expression(type, op, value, tag, args);
}

class _Statement {
  final int id;
  final String op;
  final _Expression? expression;
  final List<_Statement> body;
  final List<_Statement> otherwise;
  final int bound;
  _Statement(
    this.id,
    this.op,
    this.expression, {
    this.body = const [],
    this.otherwise = const [],
    this.bound = 0,
  });

  void write(StringBuffer result, String indent, int depth) {
    if (op == 'value' || op == 'flag') {
      result.writeln('$indent$op = ${expression!.source};');
      result.writeln("${indent}print('p$id:\${$op}:\$trace');");
    } else if (op == 'if') {
      result.writeln('${indent}if (${expression!.source}) {');
      for (final statement in body) {
        statement.write(result, '$indent  ', depth);
      }
      result.writeln('$indent} else {');
      for (final statement in otherwise) {
        statement.write(result, '$indent  ', depth);
      }
      result.writeln('$indent}');
    } else {
      result.writeln(
        '${indent}for (int iteration$depth = 0; iteration$depth < $bound; iteration$depth++) {',
      );
      for (final statement in body) {
        statement.write(result, '$indent  ', depth + 1);
      }
      result.writeln('$indent}');
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'op': op,
    if (expression != null) 'expression': expression!.toJson(),
    if (op == 'loop') 'bound': bound,
    if (op == 'loop' || op == 'if')
      'body': [for (final statement in body) statement.toJson()],
    if (op == 'if')
      'otherwise': [for (final statement in otherwise) statement.toJson()],
  };

  Iterable<_Statement> reductions() sync* {
    final current = expression;
    if (current != null) {
      for (final smaller in current.reductions()) {
        yield _Statement(
          id,
          op,
          smaller,
          body: body,
          otherwise: otherwise,
          bound: bound,
        );
      }
    }
    if (op == 'loop' && bound > 0) {
      yield _Statement(id, op, null, body: body, bound: 0);
      if (bound > 1) yield _Statement(id, op, null, body: body, bound: 1);
    }
    for (var i = 0; i < body.length; i++) {
      yield _Statement(
        id,
        op,
        expression,
        body: _without(body, i),
        otherwise: otherwise,
        bound: bound,
      );
      for (final smaller in body[i].reductions()) {
        yield _Statement(
          id,
          op,
          expression,
          body: _replace(body, i, smaller),
          otherwise: otherwise,
          bound: bound,
        );
      }
    }
    for (var i = 0; i < otherwise.length; i++) {
      yield _Statement(
        id,
        op,
        expression,
        body: body,
        otherwise: _without(otherwise, i),
        bound: bound,
      );
      for (final smaller in otherwise[i].reductions()) {
        yield _Statement(
          id,
          op,
          expression,
          body: body,
          otherwise: _replace(otherwise, i, smaller),
          bound: bound,
        );
      }
    }
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>)
    throw const FormatException('Expected model object');
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>)
    throw const FormatException('Expected model list');
  return value;
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected model string');
  return value;
}

int _integer(Object? value) {
  if (value is! int) throw const FormatException('Expected model integer');
  return value;
}

_Expression _expressionFromJson(Object? value) {
  final model = _map(value);
  final op = _string(model['op']);
  final expression = _operation(
    op,
    [
      for (final argument in _list(model['args']))
        _expressionFromJson(argument),
    ],
    op == 'int' || op == 'bool' ? _string(model['value']) : '',
    op == 'tap' ? _integer(model['tag']) : 0,
  );
  if (model['type'] != (expression.type == _Type.integer ? 'int' : 'bool'))
    throw const FormatException('Expression type mismatch');
  return expression;
}

_Statement _statementFromJson(Object? value, Set<int> ids) {
  final model = _map(value);
  final id = _integer(model['id']);
  if (id < 0 || !ids.add(id))
    throw const FormatException(
      'Statement IDs must be unique nonnegative integers',
    );
  final op = _string(model['op']);
  if (op == 'value' || op == 'flag' || op == 'if') {
    final expression = _expressionFromJson(model['expression']);
    if (expression.type != (op == 'value' ? _Type.integer : _Type.boolean))
      throw const FormatException('Statement type mismatch');
    return _Statement(
      id,
      op,
      expression,
      body: op == 'if'
          ? [
              for (final statement in _list(model['body']))
                _statementFromJson(statement, ids),
            ]
          : const [],
      otherwise: op == 'if'
          ? [
              for (final statement in _list(model['otherwise']))
                _statementFromJson(statement, ids),
            ]
          : const [],
    );
  }
  if (op != 'loop') throw FormatException('Unknown statement $op');
  final bound = _integer(model['bound']);
  if (bound < 0 || bound > 3)
    throw const FormatException('Loop bound must be between 0 and 3');
  return _Statement(
    id,
    op,
    null,
    bound: bound,
    body: [
      for (final statement in _list(model['body']))
        _statementFromJson(statement, ids),
    ],
  );
}

List<T> _without<T>(List<T> values, int index) =>
    List<T>.of(values)..removeAt(index);
List<T> _replace<T>(List<T> values, int index, T value) {
  final result = List<T>.of(values);
  result[index] = value;
  return result;
}
