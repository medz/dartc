// Traces of the stack: where the calls of the frames return to, which are
// told as places in the source only when the text is asked for.
import 'dart:_heap/machine.dart'
    show
        codeStart,
        frameAddress,
        load32,
        load64,
        load8,
        sourcePlaces,
        stackMaps;
import 'dart:_heap/returns.dart' show findReturn, findStackMap;
import 'dart:_internal' show tellAwaiters;

/// The frames when it was made, each as where its call returns to, and where
/// the bodies of `async` functions waited that wait for the one there.
final class _Trace implements StackTrace {
  final List<int> _returns, _awaiters;
  _Trace(this._returns, this._awaiters);

  late final String _text = _told(_returns, _awaiters);

  String toString() => _text;
}

/// The trace of the function that calls this.
StackTrace _traceHere() {
  final places = sourcePlaces();
  if (places == 0) return StackTrace.empty;
  final start = codeStart();
  try {
    final returns = <int>[];
    // A frame starts with the caller's, then where it returns to. Frames of C
    // need not tell their callers' frames, so they end the trace.
    final maps = stackMaps();
    for (var frame = frameAddress(); frame != 0; frame = load64(frame)) {
      final at = load64(frame + 8) - start;
      if (findStackMap(maps, at) == 0) break;
      returns.add(at);
    }
    return _Trace(returns, tellAwaiters?.call() ?? const []);
  } on OutOfMemoryError {
    // What is thrown is thrown all the same.
    return StackTrace.empty;
  }
}

/// The text of the frames that return to [returns], as the official runtime
/// writes it in programs compiled ahead of time.
String _told(List<int> returns, List<int> awaiters) {
  final table = sourcePlaces();
  final records = table + 4 + load32(table) * 8;
  final texts = records + 4 + load32(records) * 16;
  String text(int at) => _textAt(texts + at + 4, load32(texts + at));
  final result = StringBuffer();
  var count = 0;
  var last = '';
  void write(String function, String where) {
    result.writeln('${'#${count++}'.padRight(8)}$function ($where)');
    last = function;
  }

  /// Tells the frames of the call returning to [at]. Gives whether that is
  /// where a body goes on after it waited.
  bool tell(int at) {
    for (var place = findReturn(table, at); place != 0;) {
      final record = records + 4 + (place - 1) * 16;
      final function = text(load32(record)), uri = text(load32(record + 4));
      place = load32(record + 12);
      if (function == '_SuspendState._resume') return true;
      // The runtime is not told, nor what makes traces and starts bodies.
      // Nor the functions of the runtime that throw for operations.
      if (uri.startsWith('dart:_heap') ||
          function == 'StackTrace.current' ||
          function == '_startAsync' ||
          uri.startsWith('dart:core') && function.startsWith('_throw')) {
        continue;
      }
      write(function, '$uri:${load32(record + 8)}');
    }
    return false;
  }

  for (final at in returns) {
    if (!tell(at)) continue;
    result.writeln('<asynchronous suspension>');
    for (final awaiter in awaiters) {
      tell(awaiter);
      result.writeln('<asynchronous suspension>');
    }
    return result.toString();
  }
  // What calls `main` is told as the official runtime has it.
  if (last == 'main') {
    write(
      '_delayEntrypointInvocation.<anonymous closure>',
      'dart:isolate-patch/isolate_patch.dart:313',
    );
    write(
      '_RawReceivePort._handleMessage',
      'dart:isolate-patch/isolate_patch.dart:192',
    );
  }
  return result.toString();
}

/// The text of the [length] bytes of UTF-8 at [address].
String _textAt(int address, int length) {
  final units = <int>[];
  for (var i = 0; i < length;) {
    final first = load8(address + i++);
    final extra = first < 0x80
        ? 0
        : first < 0xe0
        ? 1
        : first < 0xf0
        ? 2
        : 3;
    var code = extra == 0 ? first : first & (0x3f >> extra);
    for (var k = 0; k < extra; k++) {
      code = code << 6 | load8(address + i++) & 0x3f;
    }
    units.add(code);
  }
  return String.fromCharCodes(units);
}
