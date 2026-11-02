import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Reads a file URI as UTF-8, retaining a leading BOM and original line endings.
///
/// Malformed UTF-8 becomes replacement characters. A non-file URI or missing
/// file returns `null`. Other file-system errors propagate.
Future<String?> readFileSource(Uri uri) async {
  if (uri.scheme != 'file') return null;
  File file;
  try {
    file = File.fromUri(uri);
  } on UnsupportedError catch (error) {
    throw FormatException(error.message ?? 'Unsupported file URI.', uri);
  } on ArgumentError catch (error) {
    throw FormatException('${error.message}', uri);
  }
  try {
    if (IOOverrides.current != null) return _decode(await file.readAsBytes());
    if (_reader == null && !_reading) {
      _reading = true;
      try {
        return _decode(await file.readAsBytes());
      } finally {
        _reading = false;
      }
    }
    return await (_reader ??= _FileReader()).read(file);
  } on FileSystemException catch (error) {
    if (error.osError?.errorCode == 2 ||
        Platform.isWindows && error.osError?.errorCode == 3) {
      return null;
    }
    rethrow;
  }
}

String _decode(Uint8List bytes) {
  final bom =
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
  final text = utf8.decode(bytes, allowMalformed: true);
  return bom ? '\ufeff$text' : text;
}

// A single outstanding read uses the VM I/O service without starting an isolate.
_FileReader? _reader;
bool _reading = false;

final class _FileReader {
  RawReceivePort? _port;
  SendPort? _requests;
  late final _active = <int, Completer<String>>{};
  var _next = 0;

  Future<String> read(File file) {
    if (_port != null && _requests == null || _active.length >= 16) {
      return file.readAsBytes().then(_decode);
    }
    final id = _next++;
    final result = _active[id] = Completer<String>.sync();
    if (_requests case final requests?) {
      _port!.keepIsolateAlive = true;
      requests.send((id, file.absolute.path));
    } else {
      final port = _port = RawReceivePort(_receive, 'dartc file responses');
      Isolate.spawn(
        _readFiles,
        (port.sendPort, id, file.absolute.path),
        onExit: port.sendPort,
        debugName: 'dartc file I/O',
      ).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          port.close();
          _port = null;
          _active.remove(id);
          _reader = null;
          result.complete(file.readAsBytes().then(_decode));
        },
      );
    }
    return result.future;
  }

  void _receive(Object? message) {
    if (message is SendPort) {
      _requests = message;
      Isolate.current.addOnExitListener(message);
      return;
    }
    if (message == null) {
      if (_requests case final requests?) {
        Isolate.current.removeOnExitListener(requests);
      }
      _requests = null;
      _port?.close();
      _port = null;
      _reader = null;
      final pending = _active.values.toList();
      _active.clear();
      for (final result in pending) {
        result.completeError(StateError('File reader exited during a read.'));
      }
      return;
    }
    final (id, reply) = message as (int, Object);
    final result = _active.remove(id)!;
    if (_active.isEmpty) _port!.keepIsolateAlive = false;
    if (reply case (final Object error, final StackTrace stack)) {
      result.completeError(error, stack);
    } else {
      result.complete(reply as String);
    }
  }
}

void _readFiles((SendPort, int, String) first) {
  final (replies, firstId, firstPath) = first;
  final requests = RawReceivePort(null, 'dartc file requests');
  Future<void> read((int, String)? request) async {
    if (request == null) Isolate.exit();
    final (id, path) = request;
    try {
      final file = File(path);
      final kind = FileSystemEntity.typeSync(path);
      final bytes =
          kind == FileSystemEntityType.file ||
              kind == FileSystemEntityType.notFound
          ? file.readAsBytesSync()
          : await file.readAsBytes();
      replies.send((id, _decode(bytes)));
    } catch (error, stack) {
      replies.send((id, (error, stack)));
    }
  }

  requests.handler = read;
  replies.send(requests.sendPort);
  read((firstId, firstPath));
}
