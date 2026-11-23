part of 'random_dart.dart';

/// Expressions of no variables.
extension on RandomDart {
  String _creation(String Function(Kind kind) argument) {
    final rest = _random.nextBool() ? ', ${argument(.boolean)}' : '';
    final class_ = 'C${_random.nextInt(RandomDart._classCount)}';
    return '$class_(${argument(.integer)}, ${argument(.float)}$rest)';
  }

  /// An expression that is constant.
  String _constant(Kind kind) => switch (kind) {
    .object => 'const ${_constantObject()}',
    .any => _constant(_any(Kind.values.take(5).toList())),
    .text => _text(),
    .list => 'const [${_random.nextInt(9)}, 2]',
    .map => "const {1: 'one', ${2 + _random.nextInt(9)}: 'x'}",
    .function => 'leaf${_random.nextInt(3)}',
    _ => _literal(kind),
  };

  String _constantObject() {
    final rest = _random.nextBool() ? ', ${_constantObject()}' : '';
    final values = [for (final (_, kind) in RandomDart._given) _literal(kind)];
    return 'K(${values.join(', ')}$rest)';
  }

  String _text() => _any(const [
    "''",
    "'a'",
    "'hello'",
    "'é'",
    r"'\u4e2d\u{1f600}'",
    "'abcabc'",
    "'7'",
  ]);

  String _several(String Function() make) =>
      {for (var i = _random.nextInt(4); i > 0; i--) make()}.join(', ');

  String _literal(Kind kind) => switch (kind) {
    .text => _text(),
    .list =>
      _chance(4)
          ? _constant(kind)
          : '<int>[${_several(() => _literal(.integer))}]',
    .map =>
      _chance(4)
          ? _constant(kind)
          : '<int, String>{${_several(() => '${_literal(.integer)}: ${_text()}')}}',
    .object => _chance(3) ? _constant(kind) : _creation(_literal),
    .boolean => '${_random.nextBool()}',
    .number => _literal(_any([.integer, .float])),
    .function => _isLeaf || _chance(3) ? _constant(kind) : _closure(),
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
}
