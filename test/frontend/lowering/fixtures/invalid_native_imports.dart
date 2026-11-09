// ignore_for_file: must_be_a_subtype, ffi_native_must_be_external
import 'dart:ffi';

@Native<Int64 Function(Int64)>()
external double wrong(double value);

@Native<Int64 Function(Int64)>()
int withBody(int value) => value;

int valid() => 1;
