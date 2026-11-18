import 'type.dart';
import 'value.dart';

/// A body-scoped type whose descriptor is available only after validation.
///
/// Rewrites retain the checked checkpoint. Only a complete, successful constant
/// bound proof can replace it with a descriptor without runtime validation.
final class TypeBinding._(final CheckedTypeArgument check, final Value value) {
  TypeParameterType get parameter => check.parameter;

  factory checked(CheckedTypeArgument check) => TypeBinding._(check, check);

  /// Rebinds SSA identities, rejecting arbitrary replacement of a checked fact.
  TypeBinding remap(CheckedTypeArgument check, Value value) {
    if (identical(check, value)) return TypeBinding.checked(check);
    TypeConstant? descriptor(Value value) {
      while (value is TypeView || value is UncheckedCast) {
        value = (value as Instruction).inputs.single;
      }
      return value is TypeConstant ? value : null;
    }

    final actual = descriptor(value), argument = descriptor(check.argument);
    final raw = {
      for (final entry in check.environment.entries)
        entry.key: descriptor(entry.value),
    };
    if (actual == null ||
        argument == null ||
        actual.structuralKey != argument.structuralKey ||
        raw.values.any((value) => value == null)) {
      throw StateError('A type binding cannot discard its checked checkpoint.');
    }
    final environment = {
      for (final entry in raw.entries) entry.key: entry.value!.representedType,
    };
    if (!check.parameter.bound
        .substitute(environment)
        .accepts(actual.representedType)) {
      throw StateError('Constant type argument does not satisfy its bound.');
    }
    final environmentValues = {
      for (final entry in raw.entries) entry.key: entry.value!,
    };
    environmentValues[check.parameter] = actual;
    return TypeBinding._(
      CheckedTypeArgument(check.parameter, actual, environmentValues),
      actual,
    );
  }
}
