import 'dart:math';

import 'package:analyzer/dart/element/element.dart' as analyzer;
import 'package:analyzer/dart/element/type.dart' as analyzer;
import 'package:dartc/heap.dart';
import 'package:dartc/src/translate/types.dart'
    show describeType, functionTypePrefixes;
import 'package:test/test.dart';

import '../support/compiler.dart';

const _classes = '''
import 'dart:async';
class A {} class B extends A {} class I {} class C extends B implements I {}
class G<T> {} class H<T> extends G<T> implements I {}
class P<X, Y> {} class Q<T> extends P<T, G<T>> {} class R extends Q<A> {}
class L<T extends Object> implements P<T?, T Function(int)> {}
class S implements G<S> {}
void main() {}
''';

/// Says what the program of [_classes] is.
final class _Program(final List<analyzer.InterfaceElement> classes)
    implements Program {
  @override
  SuperList? superTypesOf(int number) {
    SuperList? found;
    final owner = classes[number];
    for (final type in owner.allSupertypes) {
      if (type.isDartCoreObject) continue;
      found = SuperList(
        classes.indexOf(type.element),
        list(type.typeArguments, owner),
        found,
      );
    }
    return found;
  }

  @override
  int get functionNumber =>
      classes.indexWhere((class_) => class_.name == 'Function');

  @override
  int get recordNumber =>
      classes.indexWhere((class_) => class_.name == 'Record');

  @override
  int get futureNumber =>
      classes.indexWhere((class_) => class_.name == 'Future');

  final _names = <String, List<String>>{};
  final _shapes = <(int, int, NamedParameter?), FunctionShape>{};
  final _parameters = <(String, int, bool, NamedParameter?), NamedParameter>{};
  final _parameterNames = <String, String>{};

  RecordType _record(
    analyzer.RecordType type,
    analyzer.InterfaceElement? owner,
  ) {
    final named = type.namedFields.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final names = [for (final field in named) field.name];
    return RecordType(
      list([
        for (final field in type.positionalFields) field.type,
        for (final field in named) field.type,
      ], owner),
      _names['$names'] ??= names,
    );
  }

  TypeList? list(
    List<analyzer.DartType> types, [
    analyzer.InterfaceElement? owner,
  ]) => types.isEmpty
      ? null
      : TypeList(of(types.first, owner), list(types.sublist(1), owner));

  /// The runtime's form of [type].
  RuntimeType of(analyzer.DartType type, [analyzer.InterfaceElement? owner]) {
    final isNullable = type.nullabilitySuffix == .question;
    final RuntimeType plain = switch (type) {
      analyzer.DynamicType() => const BasicType(dynamicKind),
      analyzer.VoidType() => const BasicType(voidKind),
      analyzer.NeverType() => const BasicType(neverKind),
      analyzer.InterfaceType(isDartCoreObject: true) => const BasicType(
        objectKind,
      ),
      analyzer.InterfaceType(isDartCoreNull: true) => const BasicType(nullKind),
      analyzer.TypeParameterType(:final element) => VariableType(
        owner!.typeParameters.indexOf(element),
      ),
      analyzer.InterfaceType(isDartAsyncFutureOr: true, :final typeArguments) =>
        futureOr(of(typeArguments.single, owner)),
      analyzer.InterfaceType(:final element, :final typeArguments) =>
        InterfaceType(classes.indexOf(element), list(typeArguments, owner)),
      analyzer.FunctionType() => _function(type, owner),
      analyzer.RecordType() => _record(type, owner),
      _ => throw StateError('Unexpected $type.'),
    };
    return isNullable ? nullable(plain) : plain;
  }

  FunctionType _function(
    analyzer.FunctionType type,
    analyzer.InterfaceElement? owner,
  ) {
    final all = type.formalParameters;
    final required = all.where((p) => p.isRequiredPositional).length;
    final positional = all.where((p) => p.isPositional).length;
    NamedParameter? names;
    for (final (i, p) in all.indexed.toList().reversed) {
      if (!p.isNamed) continue;
      final name = _parameterNames[p.name!] ??= p.name!;
      names = _parameters[(name, i, p.isRequiredNamed, names)] ??=
          NamedParameter(name, i, p.isRequiredNamed, names);
    }
    final shape = _shapes[(required, positional, names)] ??= FunctionShape(
      required,
      positional,
      functionTypePrefixes(all),
      names,
    );
    return FunctionType(
      of(type.returnType, owner),
      list([for (final p in all) p.type], owner),
      shape,
    );
  }

  @override
  RuntimeType typeOf(Object object) => throw UnimplementedError();
  @override
  Object? receiverOf(Object function) => throw UnimplementedError();

  @override
  TypeList? typesOf(Object function) => throw UnimplementedError();
  @override
  String functionName(Object function) => throw UnimplementedError();
  @override
  String calledName(Object function) => throw UnimplementedError();
  @override
  String className(int number) => classes[number].displayName;
}

/// Types that differ little.
const _functions = [
  'int Function()',
  'int Function([int])',
  'int Function([num])',
  'int Function([int, int])',
  'int Function(int)',
  'int Function(num)',
  'int Function(int, int)',
  'num Function(int, [int])',
  'int Function(int, [num])',
  'int Function(num, [num, num])',
  'int Function({int a})',
  'int Function({num a})',
  'int Function({required int a})',
  'int Function({required num a, int b})',
  'num Function({int a, required int b})',
  'void Function(int, {int a})',
  'void Function(num, {num a, num b})',
  'P<Object?, Object Function(int)>',
  'P<num?, num Function(int)>',
  'P<int?, int Function(int)>',
  'L<int>',
  'L<num>',
  'Function',
  'G<Function>',
  'G<int Function()>',
];

const _records = [
  'Record',
  '()',
  '(int,)',
  '(num,)',
  '(int, int)',
  '(num, Object?)',
  '(int, {int a})',
  '(int, {num a})',
  '({int a})',
  '({num a})',
  '({int b})',
  '({int b, int a})',
  '({Object a, num b})',
  'G<Record>',
  'G<(int, int)>',
];

const _futures = [
  'FutureOr<int>',
  'FutureOr<int?>',
  'FutureOr<int>?',
  'FutureOr<num>',
  'FutureOr<Object>',
  'FutureOr<Object?>',
  'FutureOr<dynamic>',
  'FutureOr<Null>',
  'FutureOr<Never>',
  'FutureOr<FutureOr<int>>',
  'Future<int>',
  'Future<int?>',
  'Future<int>?',
  'Future<Null>',
  'Future<Never>',
  'Future<FutureOr<int>>',
];

/// The text of a random type.
String _random(Random random, int depth) {
  String inner() => _random(random, depth - 1);
  final text = switch (random.nextInt(depth > 0 ? 32 : 11)) {
    0 => 'dynamic',
    1 => 'Null',
    2 => 'Never',
    3 => 'Object',
    4 => 'int',
    5 => 'num',
    6 => 'A',
    7 => 'B',
    8 => 'C',
    9 => 'I',
    10 => 'S',
    11 || 12 => 'G<${inner()}>',
    13 || 14 => 'H<${inner()}>',
    15 || 16 => 'P<${inner()}, ${inner()}>',
    17 => 'Q<${inner()}>',
    18 => 'R',
    19 => 'L<Object>',
    20 => 'Function',
    21 => 'Record',
    25 || 26 => 'Future<${inner()}>',
    27 || 28 || 29 => 'FutureOr<${inner()}>',
    22 || 23 || 24 => _randomRecord(random, inner),
    _ => _randomFunction(random, inner),
  };
  return text != 'dynamic' && random.nextInt(4) == 0 ? '$text?' : text;
}

String _randomRecord(Random random, String Function() inner) {
  final fields = [for (var i = random.nextInt(3); i > 0; i--) inner()];
  final named = [
    for (final name in ['b', 'a'])
      if (random.nextInt(3) == 0) '${inner()} $name',
  ];
  return switch ((fields, named)) {
    ([final single], []) => '($single,)',
    (_, []) => '(${fields.join(', ')})',
    _ => '(${[...fields, '{${named.join(', ')}}'].join(', ')})',
  };
}

String _randomFunction(Random random, String Function() inner) {
  final required = [for (var i = random.nextInt(3); i > 0; i--) inner()];
  final optional = random.nextInt(3) == 0
      ? '[${[for (var i = random.nextInt(2); i >= 0; i--) inner()].join(', ')}]'
      : random.nextInt(3) == 0
      ? '{${[
          for (final name in ['a', 'b'])
            if (random.nextBool()) '${random.nextInt(3) == 0 ? 'required ' : ''}${inner()} $name',
        ].join(', ')}}'
      : '';
  final result = random.nextInt(5) == 0 ? 'void' : inner();
  final parameters = [
    ...required,
    if (optional.isNotEmpty && optional != '{}') optional,
  ];
  return '$result Function(${parameters.join(', ')})';
}

void main() {
  test('subtypes are those of the official rules', () async {
    final random = Random(5);
    final texts = [
      ..._functions,
      ..._records,
      ..._futures,
      for (var i = 0; i < 400; i++) _random(random, 3),
    ];
    final source = await load(
      '$_classes\n'
      '${[for (final (i, text) in texts.indexed) 'typedef T$i = $text;'].join('\n')}',
    );
    final library = source.main.element;
    final types = [for (final alias in library.typeAliases) alias.aliasedType];
    final program_ = _Program([
      ...library.classes,
      for (final name in [
        'int',
        'num',
        'double',
        'Function',
        'Comparable',
        'Record',
      ])
        library.typeProvider.objectElement.library.getClass(name)!,
      library.typeProvider.futureElement,
    ]);
    program = program_;
    final found = [for (final type in types) program_.of(type)];
    for (final (i, type) in found.indexed) {
      final name = describeType(types[i]).replaceAll('Never?', 'Null');
      // Some of these are the same as simpler types.
      if (name.contains('FutureOr')) continue;
      expect(typeName(type), name, reason: texts[i]);
    }
    var positive = 0;
    for (final (i, a) in types.indexed) {
      for (final (j, b) in types.indexed) {
        final expected = library.typeSystem.isSubtypeOf(a, b);
        if (expected && i != j) positive++;
        expect(
          isSubtype(found[i], found[j]),
          expected,
          reason: '${texts[i]} <: ${texts[j]}',
        );
      }
    }
    expect(
      types,
      hasLength(400 + _functions.length + _records.length + _futures.length),
    );
    expect(positive, greaterThan(5000));
  });
}
