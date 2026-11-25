import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

// Calling these needs no process, so that the compiler can compile itself.
@Native<Pointer<Uint8> Function(Size)>(symbol: 'malloc')
external Pointer<Uint8> _allocate(int bytes);

@Native<Void Function(Pointer<Uint8>)>(symbol: 'free')
external void _release(Pointer<Uint8> bytes);

// Some systems take 16 bits, which are then those.
@Native<Int32 Function(Pointer<Uint8>, Uint32)>(symbol: 'chmod')
external int _changeMode(Pointer<Uint8> path, int mode);

/// Writes a file, replacing [output] only once it is complete.
void writeOutput(Uint8List bytes, String output, {required bool isExecutable}) {
  final staged = File('$output.tmp-$pid');
  try {
    staged.writeAsBytesSync(bytes, flush: true);
    if (isExecutable) _makeExecutable(staged);
    staged.renameSync(output);
  } finally {
    if (staged.existsSync()) staged.deleteSync();
  }
}

/// Writes an executable file, replacing [output] only once it is complete.
void writeProgram(Uint8List program, String output) =>
    writeOutput(program, output, isExecutable: true);

/// Lets everyone who can read [file] run it.
void _makeExecutable(File file) {
  final mode = file.statSync().mode & 0xfff;
  final text = utf8.encode(file.path);
  final path = _allocate(text.length + 1);
  if (path == nullptr) throw FileSystemException('No memory', file.path);
  try {
    path.asTypedList(text.length + 1)
      ..setAll(0, text)
      ..last = 0;
    if (_changeMode(path, mode | (mode & 0x124) >> 2) != 0) {
      throw FileSystemException('Cannot be made executable', file.path);
    }
  } finally {
    _release(path);
  }
}
