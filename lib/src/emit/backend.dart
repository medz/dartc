import 'dart:typed_data';

import 'code.dart';
import 'machine.dart';

/// What runs a program on Linux, given its function and what it starts with.
const linuxMainSymbol = '__libc_start_main';

/// What makes code for a kind of processor.
abstract interface class Backend() {
  Machine get machine;
  List<Relocation> get relocations;

  /// The function that makes the call which a block describes.
  void emitNativeCall();

  /// The functions of C that programs can make.
  void emitCallbacks();

  /// A function of C whose work [target] does.
  void emitExport(String target);

  /// What Linux starts, which runs [main].
  void emitLinuxEntry(String main);

  Uint8List finish();
}
