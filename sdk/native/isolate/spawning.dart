// Isolates other than the first, each on a thread of its own with a copy of
// the data that each isolate has, and so a heap of its own.
import 'dart:_heap/collector.dart' show releaseHeap;
import 'dart:_heap/objects.dart' show isolateEntry, newIsolate, runEvents;
import 'dart:_heap/program.dart' show calledName;
import 'dart:_heap/machine.dart' show load64, store64;
import 'dart:_internal' show isFirstIsolate, writeText;
import 'dart:ffi' show Int32, Int64, Native;

@Native<Int32 Function(Int64)>(symbol: 'pthread_attr_init')
external int _initAttributes(int attributes);

@Native<Int32 Function(Int64, Int64)>(symbol: 'pthread_attr_setstacksize')
external int _setStackSize(int attributes, int bytes);

@Native<Int32 Function(Int64)>(symbol: 'pthread_attr_destroy')
external int _destroyAttributes(int attributes);

@Native<Int32 Function(Int64, Int64, Int64, Int64)>(symbol: 'pthread_create')
external int _createThread(int thread, int attributes, int start, int argument);

@Native<Int32 Function(Int64)>(symbol: 'pthread_detach')
external int _detachThread(int thread);

// What an isolate starts with: where its data is, the copy of what it is to do,
// and its inbox.
const _startData = 0, _startCopy = 8, _startInbox = 16, _startBytes = 24;

/// Bytes for the attributes of a thread on any system, and of its stack.
const _attributeBytes = 128, _stackBytes = 8 << 20;

/// Starts an isolate that sends [ready] its control port and capabilities, then
/// calls [entryPoint] with [message].
void _spawn(
  SendPort ready,
  Function entryPoint,
  Object? message,
  String? debugName,
) {
  final name = debugName ?? calledName(entryPoint);
  final copy = _encode([ready, entryPoint, message, name]);
  final data = newIsolate(), start = _allocate(_startBytes);
  if (data == 0 || start == 0) {
    _freeCopy(copy);
    throw IsolateSpawnException('Unable to spawn isolate: out of memory');
  }
  final inbox = _newInbox();
  store64(inbox + _name, _encode(name));
  store64(start + _startData, data);
  store64(start + _startCopy, copy);
  store64(start + _startInbox, inbox);
  final failure = _startThread(start);
  if (failure == 0) return;
  _closeInbox(inbox);
  _freeCopy(copy);
  _free(data);
  _free(start);
  throw IsolateSpawnException('Unable to spawn isolate: error $failure');
}

/// Runs the isolate at [start] on a thread of its own. Returns 0, or the error
/// that the system gives.
int _startThread(int start) {
  final attributes = _allocate(_attributeBytes), thread = _allocate(8);
  _initAttributes(attributes);
  _setStackSize(attributes, _stackBytes);
  final result = _createThread(thread, attributes, isolateEntry(), start);
  if (result == 0) _detachThread(load64(thread));
  _destroyAttributes(attributes);
  _free(attributes);
  _free(thread);
  return result;
}

/// The name of this isolate.
String _isolateName = 'main';

/// Runs an isolate other than the first, given where it [start]s. Then it
/// gives back what it has.
void _runSpawned(int start) {
  isFirstIsolate = false;
  _givenInbox = load64(start + _startInbox);
  try {
    final copy = _decode(load64(start + _startCopy)) as List<Object?>;
    final [ready as SendPort, entryPoint as Function, message, name] = copy;
    _isolateName = name as String;
    final current = Isolate.current;
    ready.send([
      current.controlPort,
      [current.pauseCapability, current.terminateCapability],
    ]);
    // Like the official runtime, it starts with a message to itself.
    final port = RawReceivePort();
    port.handler = (_) {
      port.close();
      entryPoint(message);
    };
    port.sendPort.send(null);
    runEvents();
  } catch (error, trace) {
    writeText(2, 'Unhandled exception:', true);
    writeText(2, error.toString(), true);
    writeText(2, trace.toString(), false);
  }
  _Inbox.current.close();
  releaseHeap();
}

/// What the isolate that [readyPort] is for tells about itself.
Future<Isolate> _spawnCommon(RawReceivePort readyPort) {
  final completer = Completer<Isolate>.sync();
  readyPort.handler = (readyMessage) {
    readyPort.close();
    final [SendPort controlPort, List capabilities] = readyMessage as List;
    completer.complete(
      Isolate(
        controlPort,
        pauseCapability: capabilities[0],
        terminateCapability: capabilities[1],
      ),
    );
  };
  return completer.future;
}
