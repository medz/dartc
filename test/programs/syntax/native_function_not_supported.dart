import 'dart:ffi';

@Native<Void Function(Handle)>()
external void f(Object value); // error 15: Not supported yet: this declaration for C.

void main() => f(1);
