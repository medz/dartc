// Isolates other than the first, each on a thread of its own with a copy of
// the data that each isolate has, and so a heap of its own.
import 'dart:_heap/collector.dart' show releaseHeap;
import 'dart:_heap/objects.dart' show isolateEntry, newIsolate, runEvents;
import 'dart:_heap/program.dart' show calledName;
import 'dart:_heap/machine.dart' show frameAddress, load64, store64;
import 'dart:_internal' show EventOrder, isFirstIsolate;
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
  List<Object?> settings,
) {
  final name = debugName ?? calledName(entryPoint);
  final copy = _encode([ready, entryPoint, message, name, ...settings]);
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
  _spawnedFrame = frameAddress();
  _givenInbox = load64(start + _startInbox);
  try {
    final copy = _decode(load64(start + _startCopy)) as List<Object?>;
    final [
      ready as SendPort,
      entryPoint as Function,
      message,
      name as String,
      paused as bool,
      errorsAreFatal as bool,
      onExit as SendPort?,
      onError as SendPort?,
    ] = copy;
    _isolateName = name;
    _errorsAreFatal = errorsAreFatal;
    if (onExit != null) _exitListeners.add((onExit, null));
    if (onError != null) _errorListeners.add(onError);
    final current = Isolate.current;
    if (paused) {
      _pauses.add(current.pauseCapability!);
      EventOrder.isPaused = true;
    }
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
  } on _Termination {
    // It was killed or left.
  } catch (error, trace) {
    _reportFatal(error, trace);
  }
  // Those told that it ended find it ended.
  _Inbox.current.close();
  _tellExit();
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
