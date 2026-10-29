/// A declaration checked by the frontend. Exactly one of function and global
/// identifies its target. Signature retains the dart:ffi type or function type.
class CheckedExport(
  final String symbol,
  final int signature, {
  final int function = -1,
  final int global = -1,
  // Scalar const data: int payload, binary64 bits, or bool 0/1.
  final int? constantBits,
});

List<CheckedExport> checkedExports = <CheckedExport>[];
