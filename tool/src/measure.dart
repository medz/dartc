import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'process.dart';

typedef _GetUsageNative = Int32 Function(Int32, Pointer<Void>);
typedef _GetUsage = int Function(int, Pointer<Void>);
typedef _CallocNative = Pointer<Void> Function(IntPtr, IntPtr);
typedef _Calloc = Pointer<Void> Function(int, int);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);

class _Usage {
  final List<int> fields;
  _Usage(this.fields);

  bool get isZero => fields.every((value) => value == 0);
  bool get validTimes =>
      fields[0] >= 0 &&
      fields[2] >= 0 &&
      fields[1] >= 0 &&
      fields[1] < 1000000 &&
      fields[3] >= 0 &&
      fields[3] < 1000000;
  int get userMicroseconds => fields[0] * 1000000 + fields[1];
  int get systemMicroseconds => fields[2] * 1000000 + fields[3];
  int get nativeMaxRss => fields[4];
  Map<String, Object> toJson() => {
    'userMicroseconds': userMicroseconds,
    'systemMicroseconds': systemMicroseconds,
    'nativeMaxRss': nativeMaxRss,
    'otherCounters': fields.sublist(5),
  };
}

class _UsageReader {
  final _GetUsage getUsage;
  final _Free free;
  final Pointer<Uint8> memory;

  _UsageReader._(this.getUsage, this.free, this.memory);

  factory _UsageReader() {
    if (Abi.current() != Abi.macosArm64 &&
        Abi.current() != Abi.linuxArm64 &&
        Abi.current() != Abi.linuxX64) {
      throw UnsupportedError('rusage ABI: ${Abi.current()}');
    }
    final libc = DynamicLibrary.process();
    final getUsage = libc.lookupFunction<_GetUsageNative, _GetUsage>(
      'getrusage',
    );
    final allocate = libc.lookupFunction<_CallocNative, _Calloc>('calloc');
    final free = libc.lookupFunction<_FreeNative, _Free>('free');
    // Supported LP64 ABIs: 2 x 16B timeval + 14 x 8B long, maxrss at +32.
    final memory = allocate(1, 144).cast<Uint8>();
    if (memory == nullptr) throw StateError('calloc failed');
    return _UsageReader._(getUsage, free, memory);
  }

  _Usage read() {
    if (getUsage(-1, memory.cast<Void>()) != 0) {
      throw StateError('getrusage(RUSAGE_CHILDREN) failed');
    }
    int word(int offset) => (memory + offset).cast<Int64>().value;
    // Darwin suseconds_t is Int32 followed by padding; Linux uses long.
    int micros(int offset) =>
        Platform.isMacOS ? (memory + offset).cast<Int32>().value : word(offset);
    return _Usage([
      word(0),
      micros(8),
      word(16),
      micros(24),
      for (var index = 0; index < 14; index++) word(32 + index * 8),
    ]);
  }

  void close() => free(memory.cast<Void>());
}

// Fresh driver, one direct task child. Native dartc normally has no children;
// SDK builds may have waited descendants. The parent validates stdout/artifacts
// and hashes; never spawn hash/time/helper children here.
Future<void> main(List<String> args) async {
  if (args.length < 4 ||
      args[0] != '--report' ||
      args[2] != '--' ||
      !File(args[3]).isAbsolute) {
    stderr.writeln(
      'Usage: dart tool/src/measure.dart --report <json> -- <absolute native executable> [args...]',
    );
    exitCode = 64;
    return;
  }
  final report = File(args[1]).absolute;
  final executable = File(args[3]);
  if (report.existsSync() &&
      executable.existsSync() &&
      FileSystemEntity.identicalSync(report.path, executable.path)) {
    stderr.writeln('The report must not overwrite the native executable.');
    exitCode = 64;
    return;
  }
  final issues = <String>[];
  _UsageReader? reader;
  _Usage? before;
  _Usage? after;
  try {
    reader = _UsageReader();
    before = reader.read();
    if (!before.isZero) issues.add('prior children usage is nonzero');
  } catch (error) {
    issues.add(error.toString());
  }
  final outcome = await captureProcess(
    executable.path,
    args.sublist(4),
    environment: const {'LC_ALL': 'C'},
    includeParentEnvironment: true,
  );
  if (outcome.exitCode != 0 ||
      outcome.timedOut ||
      outcome.outputLimited ||
      outcome.startError != null ||
      outcome.captureError != null) {
    issues.add('native task did not complete successfully');
  }
  try {
    after = reader?.read();
  } catch (error) {
    issues.add(error.toString());
  } finally {
    reader?.close();
  }
  if (after != null && (!after.validTimes || after.nativeMaxRss <= 0)) {
    issues.add('invalid rusage fields');
  }
  Map<String, int>? measurement;
  if (before != null && after != null && issues.isEmpty) {
    measurement = {
      'wallMicroseconds': outcome.elapsed.inMicroseconds,
      'userMicroseconds': after.userMicroseconds,
      'systemMicroseconds': after.systemMicroseconds,
      'kernelPeakRssBytes': after.nativeMaxRss * (Platform.isMacOS ? 1 : 1024),
    };
  }
  final data = {
    'driverPid': pid,
    'abi': Abi.current().toString(),
    'priorChildrenZero': before?.isZero,
    'before': before?.toJson(),
    'after': after?.toJson(),
    'nativeMaxRssUnit': Platform.isMacOS ? 'bytes' : 'KiB',
    'cpuScope': 'waited children including waited descendants',
    'rssScope': 'maximum child high-water, not concurrent process-tree total',
    'measurement': measurement,
    'issues': issues,
    'outcome': outcome.toJson(),
  };
  report.parent.createSync(recursive: true);
  report.writeAsStringSync('${jsonEncode(data)}\n');
}
