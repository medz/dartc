import 'dart:convert';
import 'dart:io';

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
    final bytes = await file.readAsBytes();
    final bom =
        bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf;
    final text = utf8.decode(bytes, allowMalformed: true);
    return bom ? '\ufeff$text' : text;
  } on FileSystemException catch (error) {
    if (error.osError?.errorCode == 2 ||
        Platform.isWindows && error.osError?.errorCode == 3) {
      return null;
    }
    rethrow;
  }
}
