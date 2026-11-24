import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';

/// The fields of an object for a generic function with type arguments, and how
/// many these are.
typedef Part = ({HirField function, HirField types, int count});

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

  /// Gives what [target] takes, given a list for [typeParameters] that is
  /// known by then, if it takes another one or none.
  final HirValue? Function(FunctionBuilder builder, HirValue list)? convert,

  /// The field of a list of the types that it has been given, if any.
  final HirField? types,

  /// What it calls instead of a [target].
  final Part? part,

  /// Makes what types in its parameters are made of known.
  final void Function(FunctionBuilder builder, HirValue self)? bind,

  /// What they are called where they are not given what they need.
  final String name = 'call',

  /// What their parameters are called, if not as they are declared.
  final String Function(int index)? parameterName,

  /// What their text says after their type.
  final String text = '',

  /// Whether closures of one object's method are equal.
  final bool isTearOff = false,
}) {
  String nameOf(FormalParameterElement parameter) =>
      parameterName?.call(parameters.indexOf(parameter)) ?? '${parameter.name}';

  void bindTypes(FunctionBuilder builder, HirValue self) =>
      bind?.call(builder, self);

  /// Makes [list] known as what is given for [typeParameters]. Gives what
  /// [target] takes, if it does.
  HirValue? bindGiven(FunctionBuilder builder, HirValue list) {
    builder.bindParameters(typeParameters, list);
    final convert = this.convert;
    return convert == null ? list : convert(builder, list);
  }

  List<HirValue> leading(FunctionBuilder builder, HirValue self) =>
      _leading(builder, self);
}
