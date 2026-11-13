// ignore_for_file: address_receiver
import 'dart:ffi';

@Native<Void Function(Pointer<Int>)>(isLeaf: true)
external void use(Pointer<Int> data);

void unused(int data) => use(data.address);
