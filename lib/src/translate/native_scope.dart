import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'native_types.dart';

/// What translating one function needs to know of the functions of C.
abstract interface class NativeScope() {
  NativeTypes get types;

  /// The function at [address] of C, which is a [native] one, as a value of
  /// [type]. Null if that is not supported yet.
  ///
  /// It is made in what is called [owner].
  HirValue? function(
    FunctionBuilder builder,
    HirValue address,
    FunctionType native,
    FunctionType type,
    String owner,
  );

  /// The address of what [element] is declared for, if C has that.
  HirValue? addressOf(FunctionBuilder builder, Element element);

  /// A function that makes structs of [type] of what they are in, and where.
  HirValue maker(FunctionBuilder builder, DartType type);

  /// The address of the function of C that calls [function], which is constant,
  /// made once for each [key]. It gives [exceptional] where that throws, if it
  /// gives anything.
  HirValue? staticCallback(
    FunctionBuilder builder,
    Object key,
    (FunctionType native, FunctionType type) types,
    HirValue Function() function,
    HirValue? Function() exceptional,
  );

  /// An object for a function of C that calls [function], at once unless it
  /// [isLater].
  HirValue? callable(
    FunctionBuilder builder,
    (FunctionType native, FunctionType type) types,
    HirValue function, {
    HirValue? exceptional,
    required bool isLater,
  });

  /// Lets [builder] do what the function [element], which is declared for one
  /// of C, does. Returns whether that is supported.
  bool define(FunctionBuilder builder, ExecutableElement element);
}
