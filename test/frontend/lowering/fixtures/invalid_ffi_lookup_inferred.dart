import 'dart:ffi';

Function unused(DynamicLibrary library) => library.lookupFunction('missing');

void main() {}
