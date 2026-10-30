import '../../runtime.dart' show nativeFramePointer;
import '../../runtime/frames.dart' show rtStackTraceString;

class StackTrace {
  final String _text;

  StackTrace.fromString(String stackTraceString) : _text = stackTraceString;

  const StackTrace._empty() : _text = '';

  static const StackTrace empty = StackTrace._empty();

  static StackTrace get current =>
      StackTrace.fromString(rtStackTraceString(nativeFramePointer()));

  String toString() => _text;
}
