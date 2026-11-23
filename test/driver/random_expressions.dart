part of 'random_dart.dart';

/// Expressions of the variables and functions there are.
extension on RandomDart {
  String _assignment(Kind kind, int depth) {
    final variable = _any(_assignable(kind));
    if (_random.nextBool()) return '$variable = ${_expression(kind, depth)}';
    final (operator, right) = switch (kind) {
      .integer =>
        _chance(3)
            ? (
                _any(['~/', '%', '<<', '>>', '>>>']),
                _mayThrow && _chance(8)
                    ? _expression(.integer, 1)
                    : '${1 + _random.nextInt(70)}',
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
      case 3 when _mayThrow && _chance(8):
        return '(${inner(.boolean)} ? ${inner(kind)} : throw ${inner(.object)})';
      case 1 when _assignable(kind).isNotEmpty:
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
    return switch (_random.nextInt(_mayThrow ? 5 : 4)) {
      4 => '$variable.o0!',
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
        final right = _mayThrow && _chance(8)
            ? inner(.integer)
            : operator == '~/' || operator == '%'
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
      case 3 when _mayThrow && _chance(2):
        return _chance(2)
            ? '(${inner(.float)}).toInt()'
            : '(${inner(.float)} ~/ ${inner(.integer)})';
      case 2 when _assignable(.integer).isNotEmpty:
        final variable = _any(_assignable(.integer));
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
