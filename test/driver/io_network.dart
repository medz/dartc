/// Programs that use the network, on local addresses only.
const networkPrograms = {
  'tcp': r'''
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  print(server.port > 0);
  server.listen((client) async {
    final text = await utf8.decoder.bind(client).first;
    client.write('echo: $text');
    await client.close();
  });
  final socket = await Socket.connect('127.0.0.1', server.port);
  socket.write('hello');
  await socket.flush();
  print(await utf8.decoder.bind(socket).join());
  await socket.close();
  await server.close();
  print((await InternetAddress.lookup('localhost')).isNotEmpty);
  print(InternetAddress('::1').type);
}
''',
  'http and websockets': r'''
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) {
        socket.add('got $message');
        socket.close();
      });
      return;
    }
    final body = await utf8.decoder.bind(request).join();
    request.response
      ..statusCode = 201
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'method': request.method, 'path': request.uri.path, 'body': body}));
    await request.response.close();
  });
  final client = HttpClient();
  final request = await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}/a/b?x=1'));
  request.write('payload');
  final response = await request.close();
  print(response.statusCode);
  print(response.headers.contentType);
  print(await utf8.decoder.bind(response).join());
  final get = await client.getUrl(Uri.parse('http://localhost:${server.port}/'));
  final r2 = await get.close();
  print(await utf8.decoder.bind(r2).join());
  final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/ws');
  ws.add('hi');
  print(await ws.first);
  await ws.close();
  client.close();
  await server.close();
  try {
    await HttpClient().getUrl(Uri.parse('http://127.0.0.1:1/'));
  } catch (e) {
    print(e.runtimeType);
  }
}
''',
  'sockets': r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> attempt(String name, FutureOr<Object?> Function() work) async {
  try {
    print('$name: ${await work()}');
  } catch (e) {
    print('$name fails: ${e.runtimeType} ${e is SocketException ? e.osError?.message : e}');
  }
}

Future<void> main() async {
  final a = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final b = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  print(a.send(utf8.encode('ping'), InternetAddress.loopbackIPv4, b.port));
  await for (final event in b) {
    if (event == RawSocketEvent.read) {
      final d = b.receive()!;
      print('${utf8.decode(d.data)} ${d.address.address} ${d.port == a.port}');
      break;
    }
  }
  a.close();
  b.close();
  await attempt('refused', () => Socket.connect('127.0.0.1', 1));
  final server = await ServerSocket.bind('127.0.0.1', 0);
  await attempt('in use', () => ServerSocket.bind('127.0.0.1', server.port));
  await attempt('shared', () async {
    final other = await ServerSocket.bind('127.0.0.1', server.port, shared: true);
    await other.close();
    return other.port == server.port;
  });
  final done = Completer<String>();
  server.listen((client) {
    client.listen((data) => client.add(data), onDone: () {
      client.close();
      done.complete('peer closed');
    });
  });
  final raw = await RawSocket.connect(InternetAddress.loopbackIPv4, server.port);
  print(raw.remotePort == server.port);
  print(raw.remoteAddress.address);
  print(raw.setOption(SocketOption.tcpNoDelay, true));
  print(raw.getRawOption(RawSocketOption.fromBool(RawSocketOption.levelTcp, 1, true)).isNotEmpty);
  raw.writeEventsEnabled = true;
  final events = <RawSocketEvent>[];
  final sub = raw.listen((event) {
    events.add(event);
    if (event == RawSocketEvent.write) raw.write(utf8.encode('abc'));
    if (event == RawSocketEvent.read) {
      print(utf8.decode(raw.read()!));
      raw.shutdown(SocketDirection.send);
    }
  });
  print(await done.future);
  await Future.delayed(const Duration(milliseconds: 100));
  await sub.cancel();
  await raw.close();
  print(events.toSet());
  await server.close();
  await attempt('lookup', () async => (await InternetAddress.lookup('localhost', type: InternetAddressType.IPv4)).first.address);
  await attempt('loopback', () async => (await NetworkInterface.list(includeLoopback: true)).any((i) => i.addresses.any((a) => a.isLoopback)));
  print(InternetAddress('127.0.0.1').rawAddress);
  print(InternetAddress.tryParse('fe80::1')?.type);
  print(InternetAddress.tryParse('nope'));
  final path = '${Directory.systemTemp.path}/dartc-unix-${pid}.sock';
  final unix = await ServerSocket.bind(InternetAddress(path, type: InternetAddressType.unix), 0);
  unix.listen((c) {
    c.write('unix');
    // What is not listened to would keep the program going.
    c.destroy();
  });
  final u = await Socket.connect(InternetAddress(path, type: InternetAddressType.unix), 0);
  print(await utf8.decoder.bind(u).join());
  u.destroy();
  await unix.close();
  print(File(path).existsSync());
}
''',
};
