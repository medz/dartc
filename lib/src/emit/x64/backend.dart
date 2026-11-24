import 'dart:typed_data';

import '../backend.dart';
import '../code.dart';
import '../machine.dart';
import 'assembler.dart';
import 'machine.dart';
import 'native.dart' as native;

/// Makes code for x64.
final class X64Backend(final Set<String> _externals) implements Backend {
  final _assembler = X64Assembler();

  @override
  late final Machine machine = X64Machine(_assembler, _externals);

  @override
  List<Relocation> get relocations => _assembler.relocations;

  @override
  void emitNativeCall() => native.emitNativeCall(_assembler);

  @override
  void emitCallbacks() => native.emitCallbacks(_assembler);

  @override
  void emitExport(String target) => native.emitExport(_assembler, target);

  @override
  void emitLinuxEntry(String main) => native.emitLinuxEntry(_assembler, main);

  @override
  Uint8List finish() => _assembler.finish();
}
