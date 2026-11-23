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

  /// The type parameters that its calls give arguments for, after what is
  /// given first.
  final List<TypeParameterElement> typeParameters = const [],

  /// Calls what it is made of with the same arguments, if it has no [target].
  final HirValue Function(
    FunctionBuilder builder,
    HirValue self,
    List<HirValue> arguments,
    int positional,
    List<String> named,
  )?
  forward,

  /// Makes what types in its parameters are made of known.
  final void Function(FunctionBuilder builder, HirValue self)? bind,

  /// What they are called where they are not given what they need.
  final String name = 'call',

  /// What their text says after their type.
  final String text = '',

  /// Whether closures of one object's method are equal.
  final bool isTearOff = false,
}) {
  void bindTypes(FunctionBuilder builder, HirValue self) =>
      bind?.call(builder, self);

  List<HirValue> leading(FunctionBuilder builder, HirValue self) =>
      _leading(builder, self);
}
