import 'dart:convert';
import 'dart:io';

/// The sources of the SDK by their paths, where `std` has the official ones,
/// `native` those patching them and `heap` the runtime.
typedef SdkFiles = Map<String, String>;

/// Official sources that are for other systems only.
final _unused = RegExp(
  r'^std/lib/(?:html/dart2js|indexed_db|js\w*|svg|web_\w+|_wasm|'
  r'_internal/(?:js|wasm|ddc_runtime|fix_data)\w*)/',
);

/// The sources in these directories.
SdkFiles readSdkFiles({
  required Directory std,
  required Directory native,
  required Directory heap,
}) {
  final files = <String, String>{};
  void read(String name, Directory directory) {
    final from = directory.uri.path;
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      final path = '$name/${file.uri.path.substring(from.length)}';
      final isSource = path.endsWith('.dart') || path.endsWith('.json');
      if (!isSource && path != 'std/version' || _unused.hasMatch(path)) {
        continue;
      }
      files[path] = file.readAsStringSync();
    }
  }

  read('std', std);
  read('native', native);
  read('heap', heap);
  return {for (final path in files.keys.toList()..sort()) path: files[path]!};
}

/// [files] as one text.
String packSdkFiles(SdkFiles files) =>
    base64.encode(gzip.encode(utf8.encode(jsonEncode(files))));

/// The files that [packSdkFiles] made [text] of.
SdkFiles unpackSdkFiles(String text) => (jsonDecode(
  utf8.decode(gzip.decode(base64.decode(text))),
) as Map<String, Object?>).cast();
