import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'closure_table.dart';
import 'members.dart';
import 'type_table.dart';
import 'types.dart';

/// The objects that functions and constructors of libraries and classes are.
final class FunctionObjects(
  final ClosureTable _closures,
  final TypeTable _types,

  /// Whether the program declares a function.
  final bool Function(ExecutableElement element) _declares,
) {
  /// The object that [element], as a function of [type], is, if the program
  /// declares it.
  HirConstObject? of(ExecutableElement element, FunctionType type) {
    if (!_declares(element)) return null;
    return type.typeParameters.isEmpty
        ? _closures.constant(element, null)
        : _closures.generic(element, type);
  }

  /// [element] as a constant of [type], given its type arguments if they are
  /// known.
  HirConstObject? constant(
    ExecutableElement element,
    DartType type,
    List<DartType>? given,
  ) {
    if (!_declares(element) || type is! FunctionType) return null;
    if (takesTypes(element) == null || type.typeParameters.isNotEmpty) {
      return of(element, type);
    }
    final types = _types.list(given ?? typeArgumentsOf(element, type));
    return types == null
        ? null
        : _closures.constant(element, types.value as HirConstObject?);
  }

  /// [element] with the type arguments [types].
  HirValue? instantiate(
    FunctionBuilder builder,
    ExecutableElement element,
    List<DartType> types,
  ) {
    if (!_declares(element)) return null;
    if (_types.list(types) case final found?) {
      return builder.add(
        HirStatic(_closures.constant(element, found.value as HirConstObject?)),
      );
    }
    final list = _types.listValue(builder, types);
    if (list == null) return null;
    final class_ = _closures.static(element).class_;
    final object = builder.create(class_);
    builder.add(HirStore(class_.fields.single, object, list));
    return object;
  }
}
