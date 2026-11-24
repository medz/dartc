import 'dart:math';

enum _Kind() {
  async,
  asyncStar,
  syncStar,
  plain,
}

/// Reproducible random programs of `async` functions and generators.
///
/// Functions call only those made before them, and loops count down, so that
/// programs end. What they print tells the order in which they do things.
final class RandomAsync(int seed) {
  final Random _random = Random(seed);
  final _out = StringBuffer();
  final _functions = <(String, _Kind)>[];

  /// The local variables that can be used here, which are numbers.
  final _scope = <String>[];
  int _names = 0, _labels = 0, _loops = 0;
  _Kind _kind = .plain;

  T _any<T>(List<T> choices) => choices[_random.nextInt(choices.length)];
  bool _chance(int of) => _random.nextInt(of) == 0;

  bool get _awaits => _kind == .async || _kind == .asyncStar;
  bool get _yields => _kind == .syncStar || _kind == .asyncStar;

  List<String> _named(_Kind kind) => [
    for (final (name, found) in _functions)
      if (found == kind) name,
  ];

  /// An expression for a number.
  String _number([int depth = 2]) {
    String inner() => _number(depth - 1);
    final simple = [
      '${_random.nextInt(9)}',
      if (_scope.isNotEmpty) ...[_any(_scope), _any(_scope)],
    ];
    if (depth == 0 || _chance(3)) return _any(simple);
    switch (_random.nextInt(_awaits ? 11 : 5)) {
      case 0:
        return '(${inner()} + ${inner()})';
      case 1:
        return '(${inner()} * 3 % 17)';
      case 2:
        return '(${inner()} > ${inner()} ? ${inner()} : ${inner()})';
      case 3:
        return '[${inner()}, ${inner()}].last';
      case 4:
        return 'log(${inner()})';
      case 5 || 6 when _named(.async).isNotEmpty:
        return '(await ${_any(_named(.async))}(${inner()}))';
      case 7:
        return '(await Future.value(${inner()}))';
      case 8:
        return '(await Future(() => ${inner().contains('await') ? '1' : '2'}))';
      case 9:
        return '(await ${inner()})';
      default:
        return '(await later(${inner()}))';
    }
  }

  String _condition() =>
      '${_number(1)} ${_any(const ['<', '>', '==', '!='])} ${_number(1)}';

  void _block(int depth, [void Function()? first]) {
    final count = _scope.length;
    _out.writeln('{');
    first?.call();
    for (var i = 1 + _random.nextInt(4); i > 0; i--) {
      _statement(depth);
    }
    _out.writeln('}');
    _scope.length = count;
  }

  void _yield() {
    final sources = [
      '[${_number(1)}, ${_number(1)}]',
      for (final name in _named(_kind)) '$name(${_number(1)})',
    ];
    if (_chance(3)) {
      final source = _any(sources);
      final isList = source.startsWith('[');
      _out.writeln(
        'yield* ${isList && _kind == .asyncStar ? 'Stream.fromIterable($source)' : source};',
      );
    } else {
      _out.writeln('yield ${_number()};');
    }
  }

  void _statement(int depth) {
    if (_yields && _chance(3)) return _yield();
    switch (_random.nextInt(depth > 0 ? 14 : 5)) {
      case 0 || 1:
        final value = _number();
        final name = 'v${_names++}';
        _out.writeln('int $name = $value;');
        _scope.add(name);
      case 2:
        _out.writeln('print(${_number()});');
      case 3 when _scope.isNotEmpty:
        _out.writeln(
          '${_any(_scope)} ${_any(const ['=', '+='])} ${_number()};',
        );
      case 4:
        _leave();
      case 5 || 6:
        _out.write('if (${_condition()}) ');
        _block(depth - 1);
        if (_chance(2)) {
          _out.write('else ');
          _block(depth - 1);
        }
      case 7 || 8:
        _loop(depth);
      case 9 || 10:
        _try(depth);
      case 11 when _scope.isNotEmpty:
        // A closure shares a variable.
        final name = 'f${_names++}', used = _any(_scope);
        _out.writeln('int $name() => $used += 1;');
        _out.writeln('log($name());');
      case 12:
        _forIn(depth);
      default:
        _out.writeln('log(${_number()});');
    }
  }

  void _leave() {
    switch (_random.nextInt(8)) {
      case 0:
        _out.writeln('if (${_condition()}) throw ${_number(0)};');
      case 1:
        final value = _yields ? '' : ' ${_number(1)}';
        _out.writeln('if (${_condition()}) return$value;');
      case 2 || 3 when _loops > 0:
        final where = _any(const ['break', 'continue']);
        _out.writeln('if (${_condition()}) $where;');
      case 4 when _awaits:
        _out.writeln('await null;');
      default:
        _out.writeln('log(${_number(1)});');
    }
  }

  void _loop(int depth) {
    final count = 'i${_names++}';
    final label = _chance(3) ? 'l${_labels++}: ' : '';
    _out.write(
      '${label}for (var $count = ${1 + _random.nextInt(3)}; $count > 0; $count--) ',
    );
    _loops++;
    _block(depth - 1, () {
      _out.writeln('tick();');
      _scope.add(count);
    });
    _loops--;
  }

  void _forIn(int depth) {
    final name = 'e${_names++}';
    final isStream = _awaits && _chance(2);
    final sources = [
      for (final name in _named(isStream ? .asyncStar : .syncStar))
        '$name(${_number(1)})',
      if (isStream)
        'Stream.fromIterable([1, ${_number(1)}])'
      else
        '[4, ${_number(1)}]',
    ];
    _out.write(
      '${isStream ? 'await ' : ''}for (final $name in ${_any(sources)}) ',
    );
    _loops++;
    _block(depth - 1, () => _out.writeln('log($name);'));
    _loops--;
  }

  void _try(int depth) {
    _out.write('try ');
    _block(depth - 1);
    final hasCatch = _chance(2);
    if (hasCatch) {
      final name = 'x${_names++}';
      _out.write('on int catch ($name) ');
      _block(depth - 1, () {
        _out.writeln("print('caught \$$name');");
        if (_chance(4)) _out.writeln('if (${_condition()}) rethrow;');
      });
    }
    if (!hasCatch || _chance(2)) {
      // Leaving a `finally` block would hide what comes before.
      final loops = _loops;
      _out.write('finally ');
      _block(depth - 1, () => _out.writeln("print('finally');"));
      _loops = loops;
    }
  }

  void _function(_Kind kind) {
    _kind = kind;
    final name = '${kind.name}${_functions.length}', parameter = 'p${_names++}';
    _scope
      ..clear()
      ..add(parameter);
    final (type, modifier) = switch (kind) {
      .async => ('Future<int>', 'async'),
      .asyncStar => ('Stream<int>', 'async*'),
      .syncStar => ('Iterable<int>', 'sync*'),
      .plain => ('int', ''),
    };
    _out.write('$type $name(int $parameter) $modifier ');
    _block(3, () => _out.writeln("tick(); print('$name \$$parameter');"));
    if (kind == .async) {
      final text = _out.toString();
      _out
        ..clear()
        ..write(text.substring(0, text.lastIndexOf('}')))
        ..writeln(
          'return ${_number(1).replaceAll(RegExp('[vie]\\d+'), '1')};\n}',
        );
    }
    _functions.add((name, kind));
  }

  /// A whole program.
  String generate() {
    _out.writeln(r'''
import 'dart:async';
int steps = 0;
void tick() { if (++steps > 700) throw 'enough'; }
int log(int n) { tick(); print('log $n'); return n % 1000; }
Future<int> later(int n) async { await null; if (n % 7 == 6) throw n; return n; }
''');
    for (var i = 0; i < 9; i++) {
      _function(
        _any(const [_Kind.async, _Kind.async, _Kind.asyncStar, _Kind.syncStar]),
      );
    }
    _out.writeln('void main() async {');
    for (final (name, kind) in _functions) {
      for (final argument in [0, 1 + _random.nextInt(8)]) {
        final call = '$name($argument)';
        final use = switch (kind) {
          .async => 'print(await $call);',
          .asyncStar => 'print(await $call.take(20).toList());',
          _ => 'print($call.take(20).toList());',
        };
        _out.writeln("try { $use } catch (e) { print('out \$e'); }");
      }
    }
    for (final name in _named(.async)) {
      _out.writeln("$name(3).then(print, onError: (e) => print('late \$e'));");
    }
    _out.writeln('}');
    return '$_out';
  }
}
