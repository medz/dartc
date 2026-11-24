import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'closure.dart';
import 'conversions.dart';
import 'scope.dart';
import 'types.dart';

/// How functions are called with lists of arguments and names.
final class ApplyTable(final ProgramScope _scope, final SourceUnit _unit) {
  /// Takes the arguments, after something else, the names of the last, and
  /// the type arguments, or null for their bounds.
  final HirSelector selector = HirSelector('apply', const [
    .reference,
    .reference,
    .reference,
  ], .reference);
  final _entries = <HirClass, HirFunction>{};
  bool _isUsed = false;

  /// Functions made here.
  Iterable<HirFunction> get functions => _entries.values;

  Map<HirSelector, Map<HirClass, HirFunction>> get dispatch => {
    if (_isUsed) selector: _entries,
  };

  HirSelector use() {
    _isUsed = true;
    return selector;
  }

  /// Adds the entries found since the last time. Returns whether there were any.
  bool update(Iterable<Closure> closures) {
    if (!_isUsed) return false;
    final before = _entries.length;
    for (final closure in closures.toList()) {
      _entries.putIfAbsent(
        closure.class_,
        () => _Application(_scope, _unit, closure, selector).build(),
      );
    }
    return _entries.length > before;
  }
}

/// Builds how the functions of one class are called.
final class _Application(
  final ProgramScope _scope,
  final SourceUnit _unit,
  final Closure _closure,
  final HirSelector _selector,
) {
  final _function = HirFunction('apply ${_closure.class_.name}', const [
    .reference,
    .reference,
    .reference,
    .reference,
  ], .reference);
  late final _builder = FunctionBuilder(_unit, _function, const []);
  late final _conversions = Conversions(_scope, _builder);

  HirValue _call(String name, List<HirValue> values) =>
      _builder.call(HirCall(_scope.runtime(name), values))!;

  HirValue _number(int value) => _builder.add(HirConst(value));
  HirValue _text(String text) => _builder.add(_scope.text(text));

  HirValue _names(Iterable<FormalParameterElement> parameters) => _scope.list(
    _builder,
    _conversions.types.dynamicType,
    [for (final parameter in parameters) _text(parameter.name!)],
  );

  HirFunction build() {
    final [self, arguments, names, _] = _builder.inputs;
    final all = _closure.parameters;
    final positional = all.where((p) => p.isPositional).toList();
    final fits = _call('applyFits', [
      arguments,
      names,
      _number(positional.where((p) => p.isRequired).length),
      _number(positional.length),
      _names(all.where((p) => p.isNamed)),
      _names(all.where((p) => p.isRequiredNamed)),
    ]);
    final result = _builder.choose(
      fits,
      .reference,
      () => _apply(positional),
      () {
        final name = _text(_closure.name);
        return _call('applyMissing', [self, arguments, names, name]);
      },
    );
    _builder
      ..end(HirReturn(result))
      ..finish();
    return _function;
  }

  HirValue _apply(List<FormalParameterElement> positional) {
    final [self, arguments, names, given] = _builder.inputs;
    if (_closure.part case (:final function, :final types, count: _)) {
      return _builder.call(
        HirVirtualCall(_selector, _builder.add(HirLoad(function, self)), [
          arguments,
          names,
          _builder.add(HirLoad(types, self)),
        ]),
      )!;
    }
    _closure.bindTypes(_builder, self);
    final types = _closure.typeParameters;
    HirValue? list;
    if (types.isNotEmpty) {
      final defaults = defaultTypesOf(types, _builder.library);
      final all = _builder.choose(
        _conversions.isNull(given),
        .reference,
        () => _scope.typeList(_builder, defaults)!,
        () => given,
      );
      list = _closure.bindGiven(_builder, all);
      _conversions.checkBounds(types);
    }
    final result = _conversions.call(_closure.target(), [
      ..._closure.leading(_builder, self),
      ?list,
      for (final parameter in _closure.parameters)
        _argument(parameter, positional, arguments, names),
    ]);
    final value = result ?? _builder.add(HirNull());
    return _conversions.coerce(value, .reference);
  }

  HirValue _argument(
    FormalParameterElement parameter,
    List<FormalParameterElement> positional,
    HirValue arguments,
    HirValue names,
  ) {
    // Where it is, or -1.
    final at = parameter.isNamed
        ? _call('applyNamed', [arguments, names, _text(parameter.name!)])
        : _call('applyPositional', [
            arguments,
            names,
            _number(positional.indexOf(parameter)),
          ]);
    final type = parameter.type;
    HirValue given() =>
        _conversions.cast(
          _call('applyArgument', [arguments, at]),
          _conversions.types.dynamicType,
          type,
          ending: " of '${parameter.name}'",
        ) ??
        (throw StateError('No test for $type.'));
    if (parameter.isRequired) return given();
    return _builder.choose(
      _builder.add(HirCompare(.less, at, _number(0))),
      valueType(type)!,
      () => _builder.add(_scope.defaultOf(parameter)),
      given,
    );
  }
}
