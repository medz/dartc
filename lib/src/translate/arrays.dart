import 'package:dartc/hir.dart';

import 'builder.dart';

/// An array of [class_] that holds [values], and [own] in its field.
HirValue newArray(
  FunctionBuilder builder,
  HirClass class_,
  HirValue own,
  List<HirValue> values,
) {
  final length = builder.add(HirConst(values.length));
  final array = builder.call(HirNewArray(class_, length))!;
  builder.add(HirStore(class_.fields.single, array, own));
  for (final (i, value) in values.indexed) {
    final index = builder.add(HirConst(i));
    builder.add(HirStoreElement(.reference, array, index, value));
  }
  return array;
}
