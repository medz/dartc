import 'dart:math';

/// A type that both languages have, and the numbers that it is made of.
sealed class _Type() {
  String get c;

  /// The type in signatures of C functions in Dart, and in Dart itself.
  String get native;
  String get dart;

  /// The numbers in [value], as C and Dart read them.
  Iterable<(String, _Scalar)> parts(String value, {required bool isDart});
}

final class _Scalar(@override final String c, @override final String native)
    extends _Type {
  bool get isFloat => native == 'Float' || native == 'Double';
  @override
  String get dart => isFloat
      ? 'double'
      : native == 'Bool'
      ? 'bool'
      : 'int';
  @override
  Iterable<(String, _Scalar)> parts(String value, {required bool isDart}) => [
    (value, this),
  ];
}

final class _Compound(
  final String name,
  final List<(_Type, int?)> fields, {
  required final bool isUnion,
  required final bool isPacked,
}) extends _Type {
  @override
  String get c => name;
  @override
  String get native => name;
  @override
  String get dart => name;

  @override
  Iterable<(String, _Scalar)> parts(
    String value, {
    required bool isDart,
  }) sync* {
    // All parts of a union are in the first one, the largest.
    for (final (i, (type, count)) in fields.take(isUnion ? 1 : 99).indexed) {
      if (count == null) {
        yield* type.parts('$value.f$i', isDart: isDart);
      } else {
        for (var j = 0; j < count; j++) {
          yield* type.parts('$value.f$i[$j]', isDart: isDart);
        }
      }
    }
  }
}

final _scalars = [
  _Scalar('int8_t', 'Int8'),
  _Scalar('uint8_t', 'Uint8'),
  _Scalar('int16_t', 'Int16'),
  _Scalar('uint16_t', 'Uint16'),
  _Scalar('int32_t', 'Int32'),
  _Scalar('uint32_t', 'Uint32'),
  _Scalar('int64_t', 'Int64'),
  _Scalar('uint64_t', 'Uint64'),
  _Scalar('float', 'Float'),
  _Scalar('double', 'Double'),
  _Scalar('bool', 'Bool'),
];

/// Reproducible random functions of C, with a program that calls them and that
/// lets them call it back.
final class RandomNative(int seed) {
  final Random _random = Random(seed);
  final _compounds = <_Compound>[];
  final _c = StringBuffer(), _dart = StringBuffer(), _main = StringBuffer();

  T _any<T>(List<T> choices) => choices[_random.nextInt(choices.length)];
  bool _chance(int of) => _random.nextInt(of) == 0;

  _Type _type() =>
      _compounds.isNotEmpty && _chance(2) ? _any(_compounds) : _any(_scalars);

  void _compound() {
    final name = 'S${_compounds.length}';
    final floats = _scalars.where((type) => type.isFloat).toList();
    final isUniform = _chance(2);
    final only = _any(floats);
    final isUnion = _chance(5);
    final fields = <(_Type, int?)>[
      for (var i = 1 + _random.nextInt(isUnion ? 1 : 4); i > 0; i--)
        (
          isUniform
              ? only
              : _chance(4)
              ? _type()
              : _any(_scalars),
          _chance(5) ? 1 + _random.nextInt(3) : null,
        ),
    ];
    if (isUnion) fields.add((_scalars.first, null));
    final made = _Compound(
      name,
      fields,
      isUnion: isUnion,
      // The official runtime passes some of these in the wrong place.
      isPacked: !isUnion && !isUniform && _chance(6),
    );
    _compounds.add(made);
    final kind = isUnion ? 'union' : 'struct';
    final packed = made.isPacked ? '__attribute__((packed)) ' : '';
    _c.writeln('typedef $kind $packed{');
    if (made.isPacked) _dart.writeln('@Packed(1)');
    _dart.writeln(
      'final class $name extends ${isUnion ? 'Union' : 'Struct'} {',
    );
    for (final (i, (type, count)) in fields.indexed) {
      _c.writeln('  ${type.c} f$i${count == null ? '' : '[$count]'};');
      if (count != null) {
        _dart.writeln('  @Array($count) external Array<${type.native}> f$i;');
      } else {
        final annotation = type is _Scalar ? '@${type.native}() ' : '';
        _dart.writeln('  ${annotation}external ${type.dart} f$i;');
      }
    }
    _c.writeln('} $name;');
    _dart.writeln('}');
  }

  String _value(_Scalar type) => type.native == 'Bool'
      ? '${_random.nextBool()}'
      : type.isFloat
      ? '${_random.nextInt(2000) / 4 - 200}'
      : '${_random.nextInt(1 << 31) - (1 << 30)}';

  /// Adds to [out] what makes a value of [type] called [name].
  void _make(StringBuffer out, _Type type, String name) {
    if (type is _Scalar) {
      out.writeln('  ${type.dart} $name = ${_value(type)};');
      return;
    }
    final kind = type is _Compound && type.isUnion ? 'Union' : 'Struct';
    out.writeln('  final $name = $kind.create<${type.dart}>();');
    for (final (part, scalar) in type.parts(name, isDart: true)) {
      out.writeln('  $part = ${_value(scalar)};');
    }
  }

  void _function(int index) {
    final types = [for (var i = _random.nextInt(11); i >= 0; i--) _type()];
    final result = _random.nextInt(types.length);
    final name = 'f$index', type = types[result];
    final isBack = _chance(3);
    final parameters = [for (final (i, t) in types.indexed) '${t.c} a$i'];
    final sums = [
      for (final (i, t) in types.indexed)
        for (final (part, _) in t.parts('a$i', isDart: false)) part,
    ];
    final declared = types.map((t) => t.native).join(', ');
    final own = types.map((t) => t.dart).join(', ');
    final given = [for (var i = 0; i < types.length; i++) 'a$i'].join(', ');
    _c
      ..writeln(
        '${type.c} $name(${[...parameters, if (isBack) '${type.c} (*back)(${types.map((t) => t.c).join(', ')})'].join(', ')}, double *total) {',
      )
      ..writeln('  *total = 0;');
    for (final (i, part) in sums.indexed) {
      _c.writeln('  *total += (double)$part * ${i + 1};');
    }
    final parts = type.parts('a$result', isDart: false).toList();
    final (part, scalar) = _any(parts);
    if (scalar.native != 'Bool') _c.writeln('  $part += 1;');
    _c.writeln(isBack ? '  return back($given);\n}' : '  return a$result;\n}');
    _main.writeln('{');
    for (final (i, t) in types.indexed) {
      _make(_main, t, 'a$i');
    }
    if (isBack) _callback(index, types, result);
    final back = isBack
        ? ', Pointer<NativeFunction<${type.native} Function($declared)>>'
        : '';
    _main
      ..writeln(
        '  final r = lib.lookupFunction<${type.native} Function($declared$back, Pointer<Double>), '
        '${type.dart} Function($own$back, Pointer<Double>)>'
        "('$name')($given${isBack ? ', Pointer.fromFunction(back$index${type is _Scalar ? ', ${type.isFloat
                        ? '0.0'
                        : type.native == 'Bool'
                        ? 'false'
                        : '0'}' : ''})' : ''}, total);",
      )
      ..writeln("  print('$name \${total.value}');");
    for (final (part, _) in type.parts('r', isDart: true)) {
      _main.writeln('  print($part);');
    }
    for (final (part, _) in types.last.parts(
      'a${types.length - 1}',
      isDart: true,
    )) {
      _main.writeln('  print($part);');
    }
    _main.writeln('}');
  }

  void _callback(int index, List<_Type> types, int result) {
    final type = types[result];
    _dart.writeln(
      '${type.dart} back$index(${[for (final (i, t) in types.indexed) '${t.dart} a$i'].join(', ')}) {',
    );
    for (final (i, t) in types.indexed) {
      for (final (part, _) in t.parts('a$i', isDart: true)) {
        _dart.writeln('  print($part);');
      }
    }
    _dart.writeln('  return a$result;\n}');
  }

  /// The source of a library, and a program that uses it at [path].
  ({String c, String dart}) generate(String path) {
    _c.writeln('#include <stdint.h>\n#include <stdbool.h>');
    _dart.writeln(
      "import 'dart:ffi';\n"
      '@Native<Pointer<Void> Function(Size)>() '
      'external Pointer<Void> malloc(int n);',
    );
    for (var i = 0; i < 8; i++) {
      _compound();
    }
    for (final compound in _compounds) {
      _c.writeln(
        'long size${compound.name}(void) { return sizeof(${compound.name}); }',
      );
      _main.writeln(
        "print([sizeOf<${compound.name}>(), lib.lookupFunction<Long Function(), int Function()>('size${compound.name}')()]);",
      );
    }
    for (var i = 0; i < 25; i++) {
      _function(i);
    }
    return (
      c: '$_c',
      dart:
          '${_dart}void main() {\n'
          "final lib = DynamicLibrary.open('$path');\n"
          'final total = malloc(8).cast<Double>();\n$_main}\n',
    );
  }
}
