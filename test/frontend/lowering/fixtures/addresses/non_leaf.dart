// ignore_for_file: address_position
import 'dart:ffi';
import 'dart:typed_data';

@Native<Void Function(Pointer<Uint8>)>()
external void use(Pointer<Uint8> data);

void unused(Uint8List data) => use(data.address);
