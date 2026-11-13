import 'dart:ffi';

void unused(DynamicLibrary library, bool leaf) {
  library.lookupFunction<Int32 Function(Int32), double Function(double)>(
    'wrong',
  );
  library.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'variable',
    isLeaf: leaf,
  );
}
