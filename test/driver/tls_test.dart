@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(8)
library;

import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../support/compiler.dart';
import '../support/hosts.dart';

/// A server and clients over TLS, with certificates of a test authority next
/// to it, and HTTPS.
const _source = r'''
import 'dart:convert';
import 'dart:io';

final dir = Platform.script.resolve('.').toFilePath();

Future<void> attempt(String name, Future<Object?> Function() work) async {
  try {
    print('$name: ${await work()}');
  } catch (e) {
    print('$name fails: ${e.runtimeType}');
  }
}

String hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

Future<void> main() async {
  final serverContext = SecurityContext()
    ..useCertificateChain('${dir}server.pem')
    ..usePrivateKey('${dir}server_key.pem');
  final server = await SecureServerSocket.bind('127.0.0.1', 0, serverContext);
  // Clients can try more than one connection, and leave the others.
  server.listen((client) async {
    final text = await utf8.decoder.bind(client).first;
    client.write('echo $text');
    await client.close();
  }, onError: (_) {});
  final trusting = SecurityContext()..setTrustedCertificates('${dir}ca.pem');
  final socket = await SecureSocket.connect(
    'localhost',
    server.port,
    context: trusting,
  );
  final cert = socket.peerCertificate!;
  print('${cert.subject} ${cert.issuer} ${cert.startValidity}');
  print('${cert.endValidity} ${hex(cert.sha1)}');
  print(cert.pem == File('${dir}server.pem').readAsStringSync());
  socket.write('hi');
  await socket.flush();
  print(await utf8.decoder.bind(socket).join());
  await socket.close();
  await attempt(
    'untrusted',
    () => SecureSocket.connect('localhost', server.port),
  );
  await attempt('bad accepted', () async {
    final s = await SecureSocket.connect(
      'localhost',
      server.port,
      onBadCertificate: (c) => c.subject == '/CN=localhost',
    );
    s.write('x');
    final r = await utf8.decoder.bind(s).join();
    await s.close();
    return r;
  });
  await attempt(
    'bad refused',
    () => SecureSocket.connect(
      'localhost',
      server.port,
      onBadCertificate: (c) => false,
    ),
  );
  await server.close();
  final https = await HttpServer.bindSecure('127.0.0.1', 0, serverContext);
  https.listen((r) => r.response
    ..write('secure ${r.uri.path}')
    ..close());
  final client = HttpClient(context: trusting);
  final request = await client.getUrl(
    Uri.parse('https://localhost:${https.port}/p'),
  );
  print(await utf8.decoder.bind(await request.close()).join());
  client.close();
  await https.close();
}
''';

/// Chooses protocols, which Secure Transport of macOS cannot do as a server.
const _protocols = r'''
import 'dart:convert';
import 'dart:io';

final dir = Platform.script.resolve('.').toFilePath();

Future<void> main() async {
  final context = SecurityContext()
    ..useCertificateChain('${dir}server.pem')
    ..usePrivateKey('${dir}server_key.pem')
    ..setAlpnProtocols(['h2', 'http/1.1'], true);
  final server = await SecureServerSocket.bind('127.0.0.1', 0, context);
  server.listen((client) async {
    client.write('${client.selectedProtocol}');
    await client.close();
    // What is not listened to would keep the program going.
    client.destroy();
  }, onError: (_) {});
  final trusting = SecurityContext()..setTrustedCertificates('${dir}ca.pem');
  for (final offered in [
    ['http/1.1'],
    ['h2', 'http/1.1'],
    ['spdy/3'],
  ]) {
    final socket = await SecureSocket.connect(
      'localhost',
      server.port,
      context: trusting,
      supportedProtocols: offered,
    );
    final told = await utf8.decoder.bind(socket).join();
    print('$offered ${socket.selectedProtocol} $told');
    socket.destroy();
  }
  await server.close();
}
''';

/// Makes a test authority, and a certificate for `localhost` that it signs,
/// in [directory]. They are made each time, so that they never expire.
void _makeCertificates(String directory) {
  void run(List<String> arguments) {
    final result = Process.runSync(
      'openssl',
      arguments,
      workingDirectory: directory,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }

  File('$directory/ext.cnf').writeAsStringSync(
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n'
    'basicConstraints=CA:FALSE\n'
    'extendedKeyUsage=serverAuth\n'
    'keyUsage=digitalSignature,keyEncipherment\n',
  );
  const days = ['-days', '30'];
  run([
    'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', //
    'ca_key.pem', '-out', 'ca.pem', ...days, '-subj', '/CN=dartc test CA',
  ]);
  run([
    'req', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'server_key.pem', //
    '-out', 'server.csr', '-subj', '/CN=localhost',
  ]);
  // Systems take certificates of servers for only so long.
  run([
    'x509', '-req', '-in', 'server.csr', '-CA', 'ca.pem', '-CAkey', //
    'ca_key.pem', '-CAcreateserial', '-out', 'server.pem', ...days, //
    '-extfile', 'ext.cnf',
  ]);
}

void main() {
  test('secure sockets do what they do officially', () => _agrees(_source));

  test('protocols are chosen as officially', () {
    return _agrees(_protocols, hosts: Host.all.where((host) => host.isLinux));
  });
}

/// Checks that [source] does on [hosts] what it does officially.
Future<void> _agrees(String source, {Iterable<Host>? hosts}) async {
  final directory = writeSources({'main.dart': source});
  final path = '${directory.path}/main.dart';
  _makeCertificates(directory.path);
  final expected = Process.runSync('$hostSdk/bin/dart', ['run', path]);
  expect(expected.exitCode, 0, reason: '${expected.stderr}');
  final program = '${directory.path}/program';
  for (final host in hosts ?? Host.all) {
    writeProgram(
      await compileProgram(path, CompileOptions(target: host.target)),
      program,
    );
    final run = await host.run(program);
    expect(run.output, expected.stdout, reason: '${host.target}');
    expect(run.code, 0, reason: '${host.target}\n${run.errors}');
  }
}
