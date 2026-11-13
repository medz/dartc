// ignore: deprecated_implement
final class EmptyRegExp() implements RegExp {
  @override
  String get pattern => '(?!)';
  @override
  bool get isCaseSensitive => true;
  @override
  bool get isMultiLine => false;
  @override
  bool get isUnicode => false;
  @override
  bool get isDotAll => false;
  @override
  RegExpMatch? firstMatch(String input) => null;
  @override
  bool hasMatch(String input) => false;
  @override
  String? stringMatch(String input) => null;
  @override
  Iterable<RegExpMatch> allMatches(String input, [int start = 0]) => const [];
  @override
  Match? matchAsPrefix(String input, [int start = 0]) => null;
}

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

String expected(String input) {
  const significant = [
    36,
    40,
    41,
    42,
    43,
    46,
    63,
    91,
    92,
    93,
    94,
    123,
    124,
    125,
  ];
  final units = <int>[];
  for (final code in input.codeUnits) {
    if (significant.contains(code)) units.add(92);
    units.add(code);
  }
  return String.fromCharCodes(units);
}

void main() {
  final escape = RegExp.escape;
  final dynamic dynamicEscape = escape;
  check(
    escape('A[\ud800]\u{1f600}') == 'A\\[\ud800\\]\u{1f600}',
    'literal UTF-16 data',
  );
  for (final input in [
    '',
    'plain-text/@:;!<>=_',
    r'\.^$|?*+()[]{}',
    String.fromCharCodes(List.generate(256, (i) => i)),
    String.fromCharCodes([0xd800, 0x24, 0xdc00, 0xd83d, 0xde00, 0x7b, 0x4e2d]),
    'start*middle?end',
  ]) {
    final result = expected(input);
    check(RegExp.escape(input) == result, 'direct escape');
    check(escape(input) == result, 'function value');
    check(dynamicEscape(input) == result, 'dynamic function value');
    check(escape(result) == expected(result), 'escaped backslashes');
  }
  for (final invalid in [null, 7, true]) {
    try {
      dynamicEscape(invalid);
      throw StateError('dynamic input accepted');
    } on TypeError {
      // The String parameter must still be checked.
    }
  }
  final text = List<String>.filled(600, '*text.[?]\u{1f600}').join();
  final escaped = escape(text);
  check(escaped == expected(text), 'large result');
  var sum = 0;
  for (var i = 0; i < 4000; i++) {
    sum += List<int>.filled(64, i).last;
  }
  check(
    sum == 7998000 && escape(text) == escaped,
    'result survives collection',
  );
  final RegExp custom = EmptyRegExp();
  check(escape(custom.pattern) == r'\(\?!\)', 'public implementation contract');
  print('regexp_escape:ok');
}
