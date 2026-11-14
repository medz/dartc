import 'dart:convert';

import '../../frontend/lowering/fixtures/effects.dart';
import '../../frontend/lowering/fixtures/extension_types.dart' as basic;
import '../../frontend/lowering/fixtures/extension_types_constructors.dart'
    as constructors;
import '../../frontend/lowering/fixtures/extension_types_generic.dart'
    as generic;
import '../../frontend/lowering/fixtures/extension_types_interfaces.dart'
    as interfaces;
import '../../frontend/lowering/fixtures/extension_type_aliases.dart'
    as aliases;
import '../../frontend/lowering/fixtures/extension_type_redirects.dart'
    as redirects;

void observe(String name, Object? Function() run, [Object? input]) {
  calls.clear();
  Object? value;
  String? error;
  try {
    value = run();
  } on AssertionError catch (failure) {
    error = 'assert:${failure.message}';
  } on int catch (failure) {
    error = 'int:$failure';
  } on String catch (failure) {
    error = failure;
  } on TypeError {
    error = 'type';
  } on RangeError {
    error = 'range';
  } on UnsupportedError {
    error = 'unsupported';
  } on StateError {
    error = 'state';
  } on NoSuchMethodError {
    error = 'method';
  }
  print(jsonEncode([name, input, value, error, calls]));
}

void main(List<String> args) {
  switch (args.single) {
    case 'basic':
      for (final (name, run) in <(String, Object? Function(int))>[
        ('basic', basic.basic),
        ('captures', basic.captures),
        ('updates', basic.updates),
        ('statics', basic.statics),
        ('record', basic.record),
        ('functions', basic.functions),
        ('nested', basic.nested),
        ('constructors', basic.constructors),
        ('cascades', basic.cascades),
        ('shorthand', basic.shorthand),
        ('identity', basic.identity),
        ('dynamicRepresentation', basic.dynamicRepresentation),
      ]) {
        for (final seed in [0, 3]) {
          observe(name, () => run(seed), seed);
        }
      }
      for (final value in <Object?>[null, 3, 'bad']) {
        observe(
          'checkedConstruction',
          () => basic.checkedConstruction(value),
          value,
        );
        observe('casts', () => basic.casts(value), value);
        observe('patterns', () => basic.patterns(value), value);
      }
      observe('nullable', () => basic.nullable(null));
      observe('nullAware', () => basic.nullAware(true));
      observe('typeValues', basic.typeValues);
      observe('nestedTypes', basic.nestedTypes);
      observe('constructorIdentity', basic.constructorIdentity);
    case 'generic':
      for (final (name, run) in <(String, Object? Function(int))>[
        ('direct', generic.direct),
        ('constructors', generic.constructors),
        ('genericMethod', generic.genericMethod),
        ('escaped', generic.escaped),
        ('dynamicConstructor', generic.dynamicConstructor),
        ('dependentConstructor', generic.dependentConstructor),
        ('operators', generic.operators),
      ]) {
        for (final seed in [0, 3]) {
          observe(name, () => run(seed), seed);
        }
      }
      for (final (name, run) in <(String, Object? Function())>[
        ('constructorIdentity', generic.constructorIdentity),
        ('constIdentity', generic.constIdentity),
        ('erasedPhantomType', generic.erasedPhantomType),
        ('reification', generic.reification),
        ('widenedView', generic.widenedView),
        ('phantomConstructorIdentity', generic.phantomConstructorIdentity),
        ('methodIdentity', generic.methodIdentity),
        ('patternPhantom', generic.patternPhantom),
        ('defaultIndependent', generic.defaultIndependent),
        ('defaultDependent', generic.defaultDependent),
        ('defaultCovariant', generic.defaultCovariant),
        ('defaultContravariant', generic.defaultContravariant),
        ('defaultRecursive', generic.defaultRecursive),
        ('defaultBounded', generic.defaultBounded),
        ('defaultBoundedSuccess', generic.defaultBoundedSuccess),
        ('recursiveConstructorDefault', generic.recursiveConstructorDefault),
        ('neverConstructor', generic.neverConstructor),
        ('aliasConstruction', aliases.construction),
        ('aliasIdentity', aliases.identity),
        ('aliasConstants', aliases.constantCalls),
        ('redirects', redirects.redirects),
      ]) {
        observe(name, run);
      }
      for (final value in <Object?>[null, 3, 'bad']) {
        observe('phantomCast', () => generic.phantomCast(value), value);
        observe('dynamicArgument', () => generic.dynamicArgument(value), value);
      }
      for (var mode = 0; mode < 4; mode++) {
        observe('aliasDynamic', () => aliases.dynamicCall(mode), mode);
      }
    case 'interfaces':
      for (final (name, run) in <(String, Object? Function(int))>[
        ('inherited', interfaces.inherited),
        ('inheritedRepresentation', interfaces.inheritedRepresentation),
        ('inheritedRecord', interfaces.inheritedRecord),
        ('inheritedFunction', interfaces.inheritedFunction),
        ('dispatched', interfaces.dispatched),
        ('coreList', interfaces.coreList),
        ('interfacePattern', interfaces.interfacePattern),
      ]) {
        for (final seed in [0, 3]) {
          observe(name, () => run(seed), seed);
        }
      }
      for (final (name, run) in <(String, Object? Function())>[
        ('multiple', interfaces.multiple),
        ('methods', interfaces.methods),
        ('defaultMethod', interfaces.defaultMethod),
        ('mostSpecific', interfaces.mostSpecific),
        ('privateLibrary', interfaces.privateLibrary),
        ('inheritedPatternViews', interfaces.inheritedPatternViews),
        ('inheritedDefaults', interfaces.inheritedDefaults),
        ('operators', interfaces.operators),
        ('patterns', interfaces.patterns),
      ]) {
        observe(name, run);
      }
      for (final value in <Object?>[2, 2.5, null]) {
        observe(
          'covariantInterface',
          () => interfaces.covariantInterface(value),
          value,
        );
        observe(
          'covariantTearOff',
          () => interfaces.covariantTearOff(value),
          value,
        );
      }
      observe('inheritedNullable', () => interfaces.inheritedNullable(null));
    case 'constructors':
      for (final (name, run) in <(String, Object? Function(int))>[
        ('primary', constructors.primary),
        ('other', constructors.other),
        ('redirect', constructors.redirect),
        ('factory', constructors.factory),
        ('generic', constructors.generic),
        ('genericPrimary', constructors.genericPrimary),
        ('ordered', constructors.ordered),
        ('nullable', constructors.nullable),
        ('genericConstructor', constructors.genericConstructor),
        ('runtimeConst', constructors.runtimeConst),
        ('tearoff', constructors.tearoff),
        ('factoryTearoff', constructors.factoryTearoff),
      ]) {
        for (final seed in [0, 1, 2, -1, -2, -3]) {
          observe(name, () => run(seed), seed);
        }
      }
      observe('constConstructors', constructors.constConstructors);
      observe('recursiveDefaults', constructors.recursiveDefaults);
      observe('staticDefaults', constructors.staticDefaults);
      for (final value in <Object?>[null, 3, 'bad']) {
        observe(
          'nullableDynamic',
          () => constructors.nullableDynamic(value),
          value,
        );
      }
      observe('afterThrow', () {
        try {
          constructors.ordered(1);
        } on String {
          return constructors.saved!();
        }
        throw StateError('Missing body exception');
      });
      observe('retainedRepresentation', () {
        constructors.Generic<List<int>>.named([7]);
        for (var i = 0; i < 2000; i++) {
          final garbage = List<String>.filled(64, 'allocation:$i');
          if (garbage.length != 64) throw StateError('allocation');
        }
        return (constructors.saved!() as List<int>).single;
      });
    default:
      throw ArgumentError(args);
  }
}
