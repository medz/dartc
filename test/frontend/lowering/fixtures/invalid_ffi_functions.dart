// ignore_for_file: argument_must_be_a_constant, must_be_a_subtype, non_constant_type_argument
import 'dart:ffi';

typedef NativeUnary = Int64 Function(Int8);
typedef FunctionPointer = Pointer<NativeFunction<NativeUnary>>;

int valid() => 1;

double Function(double) wrongSignature(FunctionPointer pointer) =>
    pointer.asFunction<double Function(double)>();

int Function(int) nonConstantLeaf(FunctionPointer pointer, bool leaf) =>
    pointer.asFunction<int Function(int)>(isLeaf: leaf);

T nonConstantFunction<T extends Function>(FunctionPointer pointer) =>
    pointer.asFunction<T>();
