import 'dart:ffi';

@Native<Int64 Function(Int8)>()
external int libraryDefault(int value);
