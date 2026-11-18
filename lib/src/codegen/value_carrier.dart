import 'package:dartc/ir.dart';

/// The scalar carrier proven by a semantic type, including lexical bounds.
///
/// Semantic declarations keep their types. Nullable or mixed scalar/reference
/// bounds retain their shared representation; an uninhabited bound supplies no
/// evidence for choosing any one scalar representation.
ValueType valueCarrier(ValueType type) {
  if (type is! TypeParameterType &&
          type is! NonNullableTypeParameterType &&
      type is! PromotedType ||
      ValueType.never.accepts(type)) {
    return type;
  }
  for (final scalar in [
    ValueType.integer,
    ValueType.boolean,
    ValueType.floating,
  ]) {
    if (scalar.accepts(type)) return scalar;
  }
  return type;
}
