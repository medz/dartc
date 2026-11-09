@Tags(['assets'])
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  late Directory work;
  late HttpServer server;
  late Uri endpoint;
  final clients = <HttpClient>[];
  final requests = <Uri>[];
  setUp(() async {
    work = (Directory(
      'build/test/sdk',
    )..createSync(recursive: true)).createTempSync('cache-');
    addTearDown(() => work.delete(recursive: true));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    endpoint = Uri.http('${server.address.address}:${server.port}', '/source');
    requests.clear();
  });
  tearDown(() async {
    for (final client in clients) {
      client.close(force: true);
    }
    clients.clear();
  });

  Future<T> redirected<T>(Future<T> Function() action, {int count = 1}) {
    final available = List.generate(count, (_) => HttpClient());
    clients.addAll(available);
    return HttpOverrides.runZoned(
      action,
      createHttpClient: (_) =>
          _RedirectClient(available.removeLast(), endpoint, requests),
    );
  }

  void serveSource() {
    server.listen((request) async {
      await request.response.addStream(
        File('build/test/sdk/source.tar.gz').openRead(),
      );
      await request.response.close();
    });
  }

  test('publishes verified sources and reuses them without network access', () async {
    serveSource();
    final resolver = SdkResolver(cacheDirectory: work);
    await redirected(() async {
      final sdk = await resolver.resolveCached();
      expect(sdk.version, '3.13.7');
      expect(
        File.fromUri(sdk.directory.uri.resolve('revision'))
            .readAsStringSync()
            .trim(),
        DartSdk.sourceRevision,
      );
      expect(
        Directory.fromUri(sdk.directory.uri.resolve('bin/')).existsSync(),
        isFalse,
      );
      expect(
        (await resolver.resolveCached()).directory.path,
        sdk.directory.path,
      );
      expect(
        requests.single.toString(),
        'https://codeload.github.com/dart-lang/sdk/tar.gz/${DartSdk.sourceRevision}',
      );
      File.fromUri(sdk.directory.uri.resolve('lib/core/core.dart'))
          .writeAsStringSync('corrupt');
      await expectLater(resolver.resolveCached(), throwsFormatException);
      expect(requests, hasLength(1));
    });
    expect(work.listSync(), hasLength(1));
  });

  test('concurrent preparation publishes one complete source tree', () async {
    serveSource();
    final resolver = SdkResolver(cacheDirectory: work);
    final results = await redirected(
      () => Future.wait([resolver.resolveCached(), resolver.resolveCached()]),
      count: 2,
    );
    expect(results[0].directory.path, results[1].directory.path);
    expect(work.listSync(), hasLength(1));
  });

  test('a source cache cannot be replaced by a directory link', () async {
    serveSource();
    final resolver = SdkResolver(cacheDirectory: work);
    await redirected(() async {
      final sdk = await resolver.resolveCached();
      final original = await sdk.directory.rename('${work.path}/original');
      await Link('${work.path}/${DartSdk.sourceRevision}')
          .create(original.absolute.path);
      await expectLater(resolver.resolveCached(), throwsFormatException);
      expect(requests, hasLength(1));
    });
  });

  for (final failure in [
    'http',
    'truncated',
    'traversal',
    'contents',
    'link',
  ]) {
    test('$failure leaves no published or partial cache', () async {
      final archive = Archive();
      const prefix = 'sdk-${DartSdk.sourceRevision}/sdk/lib/';
      archive.add(
        failure == 'link'
            ? ArchiveFile.symlink(
                '${prefix}core/core.dart',
                '../../../../outside',
              )
            : ArchiveFile.string(
                failure == 'traversal'
                    ? '$prefix../../outside'
                    : '${prefix}core/core.dart',
                'invalid sources',
              ),
      );
      final bytes = gzip.encode(TarEncoder().encode(archive));
      server.listen((request) async {
        if (failure == 'http') request.response.statusCode = 503;
        request.response.add(
          failure == 'truncated' ? bytes.take(12).toList() : bytes,
        );
        await request.response.close();
      });
      await expectLater(
        redirected(() => SdkResolver(cacheDirectory: work).resolveCached()),
        failure == 'http'
            ? throwsA(isA<HttpException>())
            : throwsFormatException,
      );
      expect(work.listSync(), isEmpty);
      expect(
        File.fromUri(work.parent.uri.resolve('outside')).existsSync(),
        isFalse,
      );
    });
  }
}

final class _RedirectClient(
  final HttpClient inner,
  final Uri endpoint,
  final List<Uri> requests,
) implements HttpClient {
  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    requests.add(url);
    return inner.getUrl(endpoint);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
