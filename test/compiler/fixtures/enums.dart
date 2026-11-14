import '../../frontend/lowering/fixtures/enum_private_storage.dart';
import '../../frontend/lowering/fixtures/enum_private_storage_use.dart';

import '../../frontend/lowering/fixtures/enums.dart' as language;
import '../../frontend/lowering/fixtures/enum_mixins.dart' as mixins;
import 'extension_types.dart' show observe;

Object? mixinArgument(Object? value, bool extracted) {
  final mixins.Generic<num> view = mixins.Parameterized.number;
  dynamic input = value;
  if (extracted) {
    dynamic echo = view.echo;
    return echo(input);
  }
  return view.echo(input);
}

void main(List<String> args) {
  switch (args.firstOrNull) {
    case 'language':
      for (final (name, run) in <(String, Object? Function())>[
        ('enumValues', language.enumValues),
        ('enumIdentity', language.enumIdentity),
        ('enumValuesImmutable', language.enumValuesImmutable),
        ('enhancedConstructors', language.enhancedConstructors),
        ('genericEnumValues', language.genericEnumValues),
        ('genericEnumTypes', language.genericEnumTypes),
        ('genericEnumStringForms', language.genericEnumStringForms),
        ('classEnumStaticConstants', language.classEnumStaticConstants),
        ('genericEnumInterfaceDispatch', language.genericEnumInterfaceDispatch),
      ]) {
        observe(name, run);
      }
      for (final (name, run) in <(String, Object? Function(int))>[
        ('enumStringForms', language.enumStringForms),
        ('enumSwitch', language.enumSwitch),
        ('enumSwitchStatement', language.enumSwitchStatement),
        ('enumConstantPattern', language.enumConstantPattern),
        ('enumObjectPattern', language.enumObjectPattern),
      ]) {
        for (var index = 0; index < 3; index++) {
          observe(name, () => run(index), index);
        }
      }
      for (final (name, run) in <(String, Object? Function(int))>[
        ('customEnumNames', language.customEnumNames),
        ('privateEnumGetter', language.privateEnumGetter),
      ]) {
        for (var index = 0; index < 2; index++) {
          observe(name, () => run(index), index);
        }
      }
      for (final amount in [-3, 0, 7]) {
        observe(
          'enhancedMembers',
          () => language.enhancedMembers(amount),
          amount,
        );
        observe(
          'enhancedClosures',
          () => language.enhancedClosures(amount),
          amount,
        );
        for (var index = 0; index < 3; index++) {
          observe(
            'enumInterfaceDispatch',
            () => language.enumInterfaceDispatch(index, amount),
            [index, amount],
          );
        }
      }
      for (final (name, run) in <(String, Object? Function(bool))>[
        ('enhancedFactories', language.enhancedFactories),
        ('enumReceivers', language.enumReceivers),
        ('enumObjectInterpolation', language.enumObjectInterpolation),
        ('enumShorthand', language.enumShorthand),
        ('nullableEnum', language.nullableEnum),
        ('enumBoundReceivers', language.enumBoundReceivers),
      ]) {
        for (final flag in [false, true]) {
          observe(name, () => run(flag), flag);
        }
      }
      for (final candidate in <Object?>[null, 4, 2.5, 'x', true]) {
        observe(
          'genericEnumChecks',
          () => language.genericEnumChecks(candidate),
          candidate,
        );
      }
      return;
    case 'mixins':
      observe('labels', mixins.labels);
      observe('parameters', mixins.parameters);
      for (final input in <Object?>[null, 5, 2.5, 'bad']) {
        for (final extracted in [false, true]) {
          observe('mixinArgument', () => mixinArgument(input, extracted), [
            input,
            extracted,
          ]);
        }
      }
      return;
  }

  for (var index = 0; index < Code.values.length; index++) {
    print(privateEnumStorage(index));
  }
  print(privateEnumInitializers());
  print(crossLibraryEnumStorage());
  final byName = Code.values.byName;
  print('${byName('second').own}:${Code.values.asNameMap()['third']!.own}');
  final ordered = Code.values.toList()..sort(Enum.compareByName);
  print(ordered.map((value) => value.name).join(','));
  print(
    '${Enum.compareByIndex(Code.third, Code.first)}:'
    '${identical(Code.first, Code.values.first)}',
  );
  try {
    byName('missing');
    throw StateError('Missing name accepted');
  } on ArgumentError catch (error) {
    print('${error.name}:${error.invalidValue}');
  }
}
