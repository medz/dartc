import 'dart:io';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

// Hosted adapters for the same binary64 word primitives used by native code.
double _hostFloat64(int bits) => (ByteData(8)..setInt64(0, bits)).getFloat64(0);
int _hostFloat64Bits(double value) =>
    (ByteData(8)..setFloat64(0, value)).getInt64(0);

int hostFloat64Add(int left, int right) =>
    _hostFloat64Bits(_hostFloat64(left) + _hostFloat64(right));
int hostFloat64Sub(int left, int right) =>
    _hostFloat64Bits(_hostFloat64(left) - _hostFloat64(right));
int hostFloat64Mul(int left, int right) =>
    _hostFloat64Bits(_hostFloat64(left) * _hostFloat64(right));
int hostFloat64Div(int left, int right) =>
    _hostFloat64Bits(_hostFloat64(left) / _hostFloat64(right));
int hostFloat64Compare(int left, int right) {
  final a = _hostFloat64(left);
  final b = _hostFloat64(right);
  if (a < b) return -1;
  if (a == b) return 0;
  if (a > b) return 1;
  return 2;
}

int hostFloat64FromInt(int value) => _hostFloat64Bits(value.toDouble());
int hostFloat64ToInt(int bits) {
  final value = _hostFloat64(bits);
  if (value.isNaN) return 0;
  if (value >= 9223372036854775808.0) return 0x7fffffffffffffff;
  if (value <= -9223372036854775808.0) return -9223372036854775808;
  return value.toInt();
}

String hostRead(String path) => File(path).readAsStringSync();

String? hostReadIfExists(String path) {
  try {
    return hostRead(path);
  } on FileSystemException catch (error) {
    final code = error.osError?.errorCode;
    if (code == 2 || code == 20) return null;
    rethrow;
  }
}

String hostCurrentDirectory() => Directory.current.path;

void hostWrite(String path, List<int> bytes) {
  File(path).parent.createSync(recursive: true);
  File(path).writeAsBytesSync(bytes);
}

Never hostExit(int status) => exit(status);

int hostTarget() => switch (Abi.current()) {
  Abi.macosArm64 => 0,
  Abi.linuxArm64 => 1,
  Abi.linuxX64 => 2,
  Abi.macosX64 => 3,
  _ => throw UnsupportedError('Compiler host ABI: ${Abi.current()}'),
};

String hostStdPath() {
  final asset = Isolate.resolvePackageUriSync(
    Uri.parse('package:dartc/src/runtime.dart'),
  );
  if (asset != null) return asset.toFilePath();
  var folder = File.fromUri(Platform.script).absolute.parent.path;
  while (folder != '/') {
    final candidate = folder + '/lib/src/runtime.dart';
    if (File(candidate).existsSync()) return candidate;
    folder = Directory(folder).parent.path;
  }
  throw StateError('Cannot locate the dartc runtime source; use --std <file>');
}

Never hostFinish(String path, int outputTarget) {
  final mode = Process.runSync('/bin/chmod', ['+x', path]);
  if (mode.exitCode != 0) stderr.write(mode.stderr);
  exit(mode.exitCode);
}
