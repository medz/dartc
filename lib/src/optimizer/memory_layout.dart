import 'package:dartc/abi.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

/// Fixed target storage facts shared by analysis and representation selection.
///
/// Replacing the program's layouts or target invalidates analyses using them.
/// NewPayload zeroes the fixed fields and inline payload after the object header.
abstract interface class FlowMemoryLayout() {
  /// Native sizes and ABI-specific integer types for the output target.
  NativeLayout get nativeLayout;

  /// The selected layout, including fixed fields before any inline payload.
  ///
  /// Missing or unresolved layouts fail instead of assuming an object shape.
  ObjectLayout objectLayout(ClassType type);
}

/// Exact fixed-slot offsets in the target object's layout.
abstract interface class FlowFieldLayout() {
  int fieldOffset(InstanceField field);
}

/// The compiler-owned representation of built-in type constants.
///
/// The view exposes immutable fields without replacing the source constant's
/// structural identity or treating user implementations of Type as metadata.
abstract interface class FlowTypeLayout() {
  /// The ordinary metadata fields emitted for this exact type constant.
  ObjectConstant typeConstant(TypeConstant value);

  /// Restores the source identity of a known closed metadata descriptor.
  ///
  /// Returns null for ordinary objects and binder-dependent descriptions.
  TypeConstant? canonicalTypeConstant(ObjectConstant value);
}

/// Immutable function fields shared with the emitted constant carrier.
abstract interface class FlowCallableLayout() {
  /// Returns a literal or an execution-table address, never a hidden call.
  Value? callableConstantField(FunctionConstant value, InstanceField field);
}
