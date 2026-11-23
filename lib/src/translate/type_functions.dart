import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'classes.dart';
import 'closure.dart';
import 'scope.dart';
import 'type_table.dart';

/// Makes the functions that tell the runtime about the program's types.
final class TypeFunctions(
  final ProgramScope _scope,
  final SourceUnit _unit,
  final ClassTable _classes,
  final TypeTable _types,
) {
  /// Gives the type of an object.
  final HirSelector typeOf = HirSelector('typeOf', const [], .reference);
  final _typeOf = <HirClass, HirFunction>{};
  final _named = <String, HirFunction>{};

  /// Gives the object whose method a function is.
  final HirSelector receiverOf = HirSelector(
    'receiverOf',
    const [],
    .reference,
  );
  final _receiverOf = <HirClass, HirFunction>{};

  /// Gives what the text of a function ends with.
  final HirSelector nameOf = HirSelector('functionName', const [], .reference);
  final _nameOfFunction = <HirClass, HirFunction>{};

  /// What the selectors call, by class.
  Map<HirSelector, Map<HirClass, HirFunction>> get dispatch => {
    if (isUsed) typeOf: _typeOf,
    if (isUsed) receiverOf: _receiverOf,
    if (isUsed) nameOf: _nameOfFunction,
  };

  bool get isUsed => _named.isNotEmpty;

  Iterable<HirFunction> get functions => [
    ..._typeOf.values,
    ..._receiverOf.values,
    ..._nameOfFunction.values,
    for (final function in _named.values)
      if (_isDefined.contains(function)) function,
  ];
  final _isDefined = <HirFunction>{};

  /// The function that the runtime calls [name].
  HirFunction named(String name) => _named.putIfAbsent(name, () {
    final function = switch (name) {
      'typeOf' || 'receiverOf' || 'functionName' => HirFunction(
        name,
        const [.reference],
        .reference,
        false,
      ),
      'superTypesOf' => HirFunction(name, const [.integer], .reference, false),
      'functionNumber' => HirFunction(name, const [], .integer, false),
      _ => HirFunction(name, const [.integer], .reference, false),
    };
    if (function.parameters case [.reference]) {
      final selector = switch (name) {
        'typeOf' => typeOf,
        'receiverOf' => receiverOf,
        _ => nameOf,
      };
      _define(function, (builder) {
        final [object] = builder.inputs;
        final result = builder.call(HirVirtualCall(selector, object, const []));
        builder.end(HirReturn(result));
      });
    }
    return function;
  });

  void _define(HirFunction function, void Function(FunctionBuilder) build) {
    final builder = FunctionBuilder(_unit, function, const []);
    build(builder);
    builder.finish();
    _isDefined.add(function);
  }

  /// Adds entries for new classes. Returns whether there were any.
  bool update(Iterable<ClassElement> classes, Iterable<Closure> closures) {
    if (!isUsed) return false;
    final before = _typeOf.length;
    for (final class_ in classes) {
      _typeOf.putIfAbsent(
        _classes.classOf(class_),
        () => _entry(class_.displayName, (builder) {
          final parameters = class_.typeParameters;
          if (parameters.isNotEmpty) {
            builder.setReceiver(builder.inputs.single, _scope.levelOf(class_));
          }
          return _types.value(builder, class_.thisType)!;
        }),
      );
    }
    for (final closure in closures) {
      _typeOf.putIfAbsent(
        closure.class_,
        () => _entry(closure.class_.name, (builder) {
          return closure.typeValue(builder);
        }),
      );
      _receiverOf.putIfAbsent(
        closure.class_,
        () => _entry('receiver of ${closure.class_.name}', (builder) {
          return closure.isTearOff
              ? closure.leading(builder, builder.inputs.single).single
              : builder.add(HirNull());
        }),
      );
      _nameOfFunction.putIfAbsent(
        closure.class_,
        () => _entry('text of ${closure.class_.name}', (builder) {
          return builder.add(_scope.text(closure.text));
        }),
      );
    }
    return _typeOf.length > before;
  }

  HirFunction _entry(
    String name,
    HirValue Function(FunctionBuilder builder) build,
  ) {
    final function = HirFunction(
      'type of $name',
      const [.reference],
      .reference,
      false,
    );
    final builder = FunctionBuilder(_unit, function, const []);
    final result = build(builder);
    builder
      ..end(HirReturn(result))
      ..finish();
    return function;
  }

  /// Makes the functions left, now that all classes in types are known.
  void finish() {
    final supers = <int, HirConstObject?>{};
    // Supertypes can be of classes not seen before.
    if (_named.containsKey('superTypesOf')) {
      for (var i = 0; i < _types.classes.length; i++) {
        supers[i] = _types.supertypesOf(_types.classes[i]);
      }
    }
    for (final MapEntry(key: name, value: function) in _named.entries) {
      switch (name) {
        case 'superTypesOf':
          _define(function, (builder) {
            _choose(builder, 0, supers.length, (builder, i) {
              final found = supers[i];
              builder.end(
                HirReturn(
                  builder.add(found == null ? HirNull() : HirStatic(found)),
                ),
              );
            });
          });
        case 'functionNumber':
          _define(function, (builder) {
            final number = _types.numberOf(_scope.functionClass);
            builder.end(HirReturn(builder.add(HirConst(number))));
          });
        case 'className':
          _names(function, _types.classes.map(_nameOf).toList());
        case 'parameterName':
          _names(function, _types.parameterNames);
      }
    }
  }

  void _names(HirFunction function, List<String> names) =>
      _define(function, (builder) {
        _choose(builder, 0, names.length, (builder, i) {
          builder.end(HirReturn(builder.add(_scope.text(names[i]))));
        });
      });

  /// What [class_] is called, as those that implement a class of the SDK are
  /// not seen.
  static String _nameOf(InterfaceElement class_) => class_.library.isDartCore
      ? switch (class_.name!) {
          '_Mint' => 'int',
          '_Double' => 'double',
          '_OneByteString' || '_TwoByteString' => 'String',
          '_GrowableList' || '_List' || '_ImmutableList' => 'List',
          final name => name,
        }
      : class_.displayName;

  /// Does [work] for the number that the function is given.
  void _choose(
    FunctionBuilder builder,
    int from,
    int to,
    void Function(FunctionBuilder builder, int number) work,
  ) {
    if (from >= to) return;
    if (from + 1 == to) return work(builder, from);
    final middle = (from + to) ~/ 2;
    final isLow = builder.add(
      HirCompare(.less, builder.inputs.single, builder.add(HirConst(middle))),
    );
    builder.branch(
      isLow,
      () => _choose(builder, from, middle, work),
      () => _choose(builder, middle, to, work),
    );
  }
}
