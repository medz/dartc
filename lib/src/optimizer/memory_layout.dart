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
