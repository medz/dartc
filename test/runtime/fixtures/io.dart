import 'dart:ffi';

import 'package:dartc/interop.dart';

import '../../../runtime/platform/io.dart' as runtime;

@Export<Int64 Function(Int64, Pointer<Uint8>, Int64)>()
int writeDescriptor(int descriptor, Pointer<Uint8> bytes, int count) =>
    runtime.writeDescriptor(descriptor, bytes, count);
