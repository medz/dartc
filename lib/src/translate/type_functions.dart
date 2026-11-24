import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'classes.dart';
import 'closure.dart';
import 'conversions.dart';
import 'scope.dart';
import 'type_table.dart';

/// The functions for closures of each class that the runtime calls [name].
final class _ClosureTable(
  final String name,
  final HirValue Function(FunctionBuilder builder, Closure closure) build,
) {
  late final selector = HirSelector(name, const [], .reference);
  final entries = <HirClass, HirFunction>{};
}

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

  /// What tells something about functions that are values.
  late final _ofFunctions = [
    _ClosureTable('receiverOf', _receiverOf),
    _ClosureTable('typesOf', _typesOf),
    _ClosureTable(
      'functionName',
      (builder, closure) => builder.add(_scope.text(closure.text)),
    ),
  ];

  /// What the selectors call, by class.
  Map<HirSelector, Map<HirClass, HirFunction>> get dispatch => {
    if (isUsed) typeOf: _typeOf,
    if (isUsed)
      for (final table in _ofFunctions) table.selector: table.entries,
  };

  bool get isUsed => _named.isNotEmpty;

  Iterable<HirFunction> get functions => [
    ..._typeOf.values,
    for (final table in _ofFunctions) ...table.entries.values,
    for (final function in _named.values)
      if (_isDefined.contains(function)) function,
  ];
  final _isDefined = <HirFunction>{};

  /// The function that the runtime calls [name].
  HirFunction named(String name) => _named.putIfAbsent(name, () {
    final table = _ofFunctions.where((table) => table.name == name);
    final function = switch (name) {
      _ when name == 'typeOf' || table.isNotEmpty => HirFunction(
        name,
        const [.reference],
        .reference,
        false,
      ),
      'superTypesOf' => HirFunction(name, const [.integer], .reference, false),
      'functionNumber' ||
      'recordNumber' ||
      'futureNumber' => HirFunction(name, const [], .integer, false),
      _ => HirFunction(name, const [.integer], .reference, false),
    };
    if (function.parameters case [.reference]) {
      final selector = name == 'typeOf' ? typeOf : table.single.selector;
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
  bool update(Iterable<InterfaceElement> classes, Iterable<Closure> closures) {
    if (!isUsed) return false;
    final before = _typeOf.length;
    for (final class_ in classes) {
      _typeOf.putIfAbsent(
        _classes.classOf(class_),
        () => _entry(class_.displayName, (builder) {
          if (class_ == _scope.recordClass) {
            final type = HirCall(_scope.runtime('recordType'), builder.inputs);
            return builder.call(type)!;
          }
          final parameters = class_.typeParameters;
          if (parameters.isNotEmpty) {
            builder.setReceiver(builder.inputs.single, _scope.levelOf(class_));
          }
          return _types.value(builder, _toldType(class_))!;
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
      for (final table in _ofFunctions) {
        table.entries.putIfAbsent(closure.class_, () {
          return _entry('${table.name} ${closure.class_.name}', (builder) {
            return table.build(builder, closure);
          });
        });
      }
    }
    return _typeOf.length > before;
  }

  HirValue _receiverOf(FunctionBuilder builder, Closure closure) {
    final object = builder.inputs.single;
    if (closure.part case final part?) {
      return builder.add(HirLoad(part.function, object));
    }
    if (!closure.isTearOff) return builder.add(HirNull());
    final receiver = closure.leading(builder, object).single;
    return Conversions(_scope, builder).coerce(receiver, .reference);
  }

  HirValue _typesOf(FunctionBuilder builder, Closure closure) => builder.add(
    closure.types == null
        ? HirNull()
        : HirLoad(closure.types!, builder.inputs.single),
  );

  /// The type of objects of [class_], which can be the only class of those of
  /// another one that programs know.
  static InterfaceType _toldType(InterfaceElement class_) {
    final provider = class_.library.typeProvider;
    if (!class_.library.isDartCore) return class_.thisType;
    return switch (class_.name) {
      '_Mint' => provider.intType,
      '_Double' => provider.doubleType,
      '_OneByteString' || '_TwoByteString' => provider.stringType,
      _ => class_.thisType,
    };
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
        case 'functionNumber' || 'recordNumber' || 'futureNumber':
          _define(function, (builder) {
            final number = _types.numberOf(switch (name) {
              'recordNumber' => _scope.recordClass.interfaces.single.element,
              'futureNumber' => _scope.futureClass,
              _ => _scope.functionClass,
            });
            builder.end(HirReturn(builder.add(HirConst(number))));
          });
        case 'className':
          _names(function, _types.classes.map(_nameOf).toList());
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
  static String _nameOf(InterfaceElement class_) {
    final name = class_.displayName;
    return switch ('${class_.library.uri}') {
      'dart:core' => switch (name) {
        '_Mint' => 'int',
        '_Double' => 'double',
        '_OneByteString' || '_TwoByteString' => 'String',
        '_GrowableList' || '_List' || '_ImmutableList' => 'List',
        _ => name,
      },
      'dart:async' => name == '_Future' ? 'Future' : name,
      'dart:typed_data' => switch (_typedData.firstMatch(name)) {
        null => name,
        final match => '${match[1] ?? match[2]}List',
      },
      _ => name,
    };
  }

  /// The names of the classes of typed data that is not part of other.
  static final _typedData = RegExp(
    r'^_(?:((?:Int|Uint|Float)[0-9x]+(?:Clamped)?)List'
    r'|External((?:Int|Uint|Float)[0-9x]+(?:Clamped)?)Array)$',
  );

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
