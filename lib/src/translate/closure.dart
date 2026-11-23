import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';

/// Functions that are values, as objects of one class.
///
/// Calling one calls [target], first giving what [_leading] gives for the
/// object, then the parameters of [type] as they are declared.
final class Closure(
  final HirClass class_,
  final FunctionType type,
  final List<FormalParameterElement> parameters,
  final HirFunction Function() target,
  final List<HirValue> Function(FunctionBuilder builder, HirValue self)
  _leading, {

  /// Gives the type of one of them, as an object of the runtime.
  required final HirValue Function(FunctionBuilder builder) typeValue,

  /// Whether closures of one object's method are equal.
  final bool isTearOff = false,
}) {
  List<HirValue> leading(FunctionBuilder builder, HirValue self) =>
      _leading(builder, self);
}
