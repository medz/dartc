// What a program knows of isolates.

@patch
final class Isolate {
  static final Isolate _current = _makeCurrent();

  static Isolate _makeCurrent() {
    final inbox = _Inbox.current;
    inbox.control = inbox.newPort();
    return Isolate(
      _SendPortImpl(inbox.control, inbox.address),
      pauseCapability: Capability(),
      terminateCapability: Capability(),
    );
  }

  @patch
  static Isolate get current => _current;

  @patch
  String? get debugName => controlPort == _current.controlPort
      ? _isolateName
      : _nameOf((controlPort as _SendPortImpl)._inbox);

  @patch
  static Future<Uri?> get packageConfig => throw _unsupported('packageConfig');

  @patch
  static Uri? get packageConfigSync => throw _unsupported('packageConfig');

  @patch
  static Future<Uri?> resolvePackageUri(Uri packageUri) =>
      throw _unsupported('resolvePackageUri');

  @patch
  static Uri? resolvePackageUriSync(Uri packageUri) =>
      throw _unsupported('resolvePackageUriSync');

  @patch
  static Future<Isolate> spawn<T>(
    void entryPoint(T message),
    T message, {
    bool paused = false,
    bool errorsAreFatal = true,
    SendPort? onExit,
    SendPort? onError,
    String? debugName,
  }) async {
    final ready = RawReceivePort(null, 'Isolate.spawn ready');
    try {
      _spawn(ready.sendPort, entryPoint, message, debugName, [
        paused,
        errorsAreFatal,
        onExit,
        onError,
      ]);
      return await _spawnCommon(ready);
    } catch (error) {
      ready.close();
      rethrow;
    }
  }

  @patch
  static Future<Isolate> spawnUri(
    Uri uri,
    List<String> args,
    message, {
    bool paused = false,
    SendPort? onExit,
    SendPort? onError,
    bool errorsAreFatal = true,
    bool? checked,
    Map<String, String>? environment,
    @Deprecated('The packages/ dir is not supported in Dart 2')
    Uri? packageRoot,
    Uri? packageConfig,
    bool automaticPackageResolution = false,
    String? debugName,
  }) => throw _unsupported('spawnUri');

  @patch
  void _pause(Capability resumeCapability) => _sendControl(controlPort, [
    _pauseMessage,
    pauseCapability,
    resumeCapability,
  ]);

  @patch
  void resume(Capability resumeCapability) => _sendControl(controlPort, [
    _resumeMessage,
    pauseCapability,
    resumeCapability,
  ]);

  @patch
  void addOnExitListener(SendPort responsePort, {Object? response}) =>
      _sendControl(controlPort, [_addExitMessage, responsePort, response]);

  @patch
  void removeOnExitListener(SendPort responsePort) =>
      _sendControl(controlPort, [_removeExitMessage, responsePort]);

  @patch
  void setErrorsFatal(bool errorsAreFatal) => _sendControl(controlPort, [
    _fatalMessage,
    terminateCapability,
    errorsAreFatal,
  ]);

  @patch
  void kill({int priority = beforeNextEvent}) =>
      _sendControl(controlPort, [_killMessage, terminateCapability, priority]);

  @patch
  void ping(
    SendPort responsePort, {
    Object? response,
    int priority = immediate,
  }) => _sendControl(controlPort, [
    _pingMessage,
    responsePort,
    priority,
    response,
  ]);

  @patch
  void addErrorListener(SendPort port) =>
      _sendControl(controlPort, [_addErrorMessage, port]);

  @patch
  void removeErrorListener(SendPort port) =>
      _sendControl(controlPort, [_removeErrorMessage, port]);

  @patch
  static Never exit([SendPort? finalMessagePort, Object? message]) {
    finalMessagePort?.send(message);
    _terminate('Isolate.exit');
  }
}

@patch
abstract final class TransferableTypedData {
  @patch
  factory TransferableTypedData.fromList(List<TypedData> list) =>
      throw _unsupported('TransferableTypedData');
}

UnsupportedError _unsupported(String what) =>
    UnsupportedError('Isolate.$what is not supported yet.');
