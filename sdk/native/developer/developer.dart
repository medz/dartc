// What programs do without a debugger or service, as with the official
// compiler in product mode.

@patch
bool debugger({bool when = true, String? message}) => when;

@patch
Object? inspect(Object? object) => object;

@patch
int get reachabilityBarrier => 0;

@patch
abstract final class NativeRuntime {
  @patch
  static String? get buildId => null;

  @patch
  static void writeHeapSnapshotToFile(String filepath) =>
      throw UnsupportedError(
        'Heap snapshots are only supported in non-product mode.',
      );

  @patch
  static void streamTimelineTo(
    TimelineRecorder recorder, {
    String? path,
    List<TimelineStream> streams = const [
      TimelineStream.dart,
      TimelineStream.gc,
    ],
    bool enableProfiler = false,
    Duration samplingInterval = const Duration(microseconds: 1000),
  }) {
    if (samplingInterval.inMicroseconds < 50) {
      throw ArgumentError.value(
        samplingInterval,
        'samplingInterval',
        'should be at least 50 us',
      );
    }
    if (recorder == TimelineRecorder.systrace && path != null) {
      throw ArgumentError.value(
        path,
        'path',
        '$recorder writes output to the global ftrace buffer and '
            'can not redirect output to a specific file',
      );
    }
    if (recorder != TimelineRecorder.systrace && path == null) {
      throw ArgumentError.value(
        path,
        'path',
        '$recorder needs an output file to write timeline data to',
      );
    }
    if (recorder != TimelineRecorder.perfetto && enableProfiler) {
      throw ArgumentError.value(
        enableProfiler,
        'enableProfiler',
        '$recorder does not support encoding profiling data, '
            'disable profiler or switch to TimelineRecorder.perfetto',
      );
    }
  }

  @patch
  static void stopStreamingTimeline() {}
}

@patch
abstract final class UserTag {
  @patch
  factory UserTag(String label) => _UserTag._all[label] ??= _UserTag(label);

  @patch
  static UserTag get defaultTag => _UserTag._default;
}

final class _UserTag implements UserTag {
  final String label;
  _UserTag(this.label);

  /// The tags by their labels, which are each made once.
  static final _all = <String, _UserTag>{'Default': _default};
  static final _default = _UserTag('Default');
  static UserTag _current = _default;

  UserTag makeCurrent() {
    final before = _current;
    _current = this;
    return before;
  }

  String toString() => label;
}

@patch
UserTag getCurrentTag() => _UserTag._current;

@patch
bool get extensionStreamHasListener => false;

@patch
void _postEvent(String eventKind, String eventData) {}

@patch
ServiceExtensionHandler? _lookupExtension(String method) => null;

@patch
_registerExtension(String method, ServiceExtensionHandler handler) {}

@patch
int _getServiceMajorVersion() => 0;

@patch
int _getServiceMinorVersion() => 0;

@patch
String? _getObjectId(Object object) => null;

@patch
final class Service {
  @patch
  static Future<ServiceProtocolInfo> getInfo() async =>
      ServiceProtocolInfo(null);

  @patch
  static Future<ServiceProtocolInfo> controlWebServer({
    bool enable = false,
    bool? silenceOutput,
  }) async => ServiceProtocolInfo(null);
}
