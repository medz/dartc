import 'dart:io';

import 'package:dartc/sdk.dart';

Future<void> main(List<String> args) => HttpOverrides.runZoned(
  () async {
    final sdk = await SdkResolver(cacheDirectory: Directory(args.first))
        .resolve(source: args.length > 1 ? args[1] : null);
    stdout.writeln(sdk.directory.path);
  },
  createHttpClient: (_) =>
      throw StateError('The resolution probe must work offline.'),
);
