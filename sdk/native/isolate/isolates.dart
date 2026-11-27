// What a program knows of isolates. It has only the first one so far.

@patch
final class Isolate {
  static final Isolate _current = _makeCurrent();

  static Isolate _makeCurrent() {
    final inbox = _Inbox.current;
    return Isolate(
      _SendPortImpl(inbox.newPort(), inbox.address),
      pauseCapability: Capability(),
      terminateCapability: Capability(),
    );
  }

  @patch
  static Isolate get current => _current;

  @patch
  String? get debugName => controlPort == _current.controlPort ? 'main' : null;

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
  }) => throw _unsupported('spawn');

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
  void _pause(Capability resumeCapability) => throw _unsupported('pause');

  @patch
  void resume(Capability resumeCapability) => throw _unsupported('resume');

  @patch
  void addOnExitListener(SendPort responsePort, {Object? response}) =>
      throw _unsupported('addOnExitListener');

  @patch
  void removeOnExitListener(SendPort responsePort) =>
      throw _unsupported('removeOnExitListener');

  @patch
  void setErrorsFatal(bool errorsAreFatal) =>
      throw _unsupported('setErrorsFatal');

  @patch
  void kill({int priority = beforeNextEvent}) => throw _unsupported('kill');

  @patch
  void ping(
    SendPort responsePort, {
    Object? response,
    int priority = immediate,
  }) => throw _unsupported('ping');

  @patch
  void addErrorListener(SendPort port) =>
      throw _unsupported('addErrorListener');

  @patch
  void removeErrorListener(SendPort port) =>
      throw _unsupported('removeErrorListener');

  @patch
  static Never exit([SendPort? finalMessagePort, Object? message]) =>
      throw _unsupported('exit');
}

@patch
abstract final class TransferableTypedData {
  @patch
  factory TransferableTypedData.fromList(List<TypedData> list) =>
      throw _unsupported('TransferableTypedData');
}

UnsupportedError _unsupported(String what) =>
    UnsupportedError('Isolate.$what is not supported yet.');
