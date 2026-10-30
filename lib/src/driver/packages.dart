import '../host.dart';
import '../diagnostic.dart';
import '../package_config.dart';
import '../source_uri.dart';

PackageConfig? compilerPackages(String inputUri, String cwd, String? explicit) {
  String path;
  String uri;
  String? text;
  if (explicit != null) {
    if (explicit == '') {
      throw Diagnostic('Missing value for --packages', exitCode: 64);
    }
    uri = sourceInputUri(cwd, explicit);
    path = sourceUriPath('/', uri);
    text = hostReadIfExists(path);
    if (text == null) {
      throw Diagnostic(
        'Package configuration not found: ' + path,
        exitCode: 64,
      );
    }
  } else {
    var directory = inputUri.substring(0, inputUri.lastIndexOf('/') + 1);
    while (true) {
      uri = directory + '.dart_tool/package_config.json';
      path = sourceUriPath('/', uri);
      text = hostReadIfExists(path);
      if (text != null) break;
      if (directory == 'file:///') return null;
      directory = sourceResolveFileUri(directory, '../');
    }
  }
  var config = parsePackageConfig(path, text);
  resolvePackageConfig(config, uri);
  return config;
}
