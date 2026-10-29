import 'errors.dart' show UnsupportedError;

abstract class Exception {
  factory Exception([message]) => _Exception(message);
}

class _Exception implements Exception {
  final dynamic message;

  _Exception([this.message]);

  String toString() => message == null ? 'Exception' : 'Exception: $message';
}

class FormatException implements Exception {
  final String message;
  final dynamic source;
  final int? offset;

  const FormatException([this.message = '', this.source, this.offset]);

  String toString() {
    var report = message.isEmpty
        ? 'FormatException'
        : 'FormatException: $message';
    final input = source;
    var position = offset;
    if (input is! String)
      return position == null ? report : '$report (at offset $position)';
    if (position != null && (position < 0 || position > input.length))
      position = null;
    if (position == null) {
      final excerpt = input.length > 78
          ? '${input.substring(0, 75)}...'
          : input;
      return '$report\n$excerpt';
    }
    var line = 1;
    var start = 0;
    var afterCr = false;
    for (var i = 0; i < position; i++) {
      final unit = input.codeUnitAt(i);
      if (unit == 10) {
        if (start != i || !afterCr) line++;
        start = i + 1;
        afterCr = false;
      } else if (unit == 13) {
        line++;
        start = i + 1;
        afterCr = true;
      }
    }
    report += line > 1
        ? ' (at line $line, character ${position - start + 1})\n'
        : ' (at character ${position + 1})\n';
    var end = input.length;
    for (var i = position; i < input.length; i++) {
      final unit = input.codeUnitAt(i);
      if (unit == 10 || unit == 13) {
        end = i;
        break;
      }
    }
    var prefix = '';
    var suffix = '';
    if (end - start > 78) {
      if (position - start < 75) {
        end = start + 75;
        suffix = '...';
      } else if (end - position < 75) {
        start = end - 75;
        prefix = '...';
      } else {
        start = position - 36;
        end = position + 36;
        prefix = suffix = '...';
      }
    }
    final mark = StringBuffer();
    for (var i = 0; i < position - start + prefix.length; i++) mark.write(' ');
    return '$report$prefix${input.substring(start, end)}$suffix\n$mark^\n';
  }
}

class IntegerDivisionByZeroException implements Exception, UnsupportedError {
  const IntegerDivisionByZeroException();

  String? get message => 'Division resulted in non-finite value';
  StackTrace? get stackTrace => null;
  String toString() => 'IntegerDivisionByZeroException';
}
