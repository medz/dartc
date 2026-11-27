import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../support/compiler.dart';
import '../support/hosts.dart';

/// Passes the address of an element and of a field to C, which the interpreters
/// cannot call.
const _source = r'''
import 'dart:ffi';
import 'dart:typed_data';

final class S extends Struct {
  @Int16()
  external int v;
}

@Native<Int64 Function(Pointer<Uint8>)>(isLeaf: true)
external int strlen(Pointer<Uint8> s);

@Native<Int64 Function(Pointer<Int16>)>(symbol: 'strlen', isLeaf: true)
external int length(Pointer<Int16> s);

void main() {
  final bytes = Uint8List.fromList([65, 66, 67, 0]);
  print(strlen(bytes[1].address));
  final s = Struct.create<S>()..v = 65;
  print(length(s.v.address));
}
''';

void main() {
  test('passes addresses of elements and of fields to C', () async {
    final directory = writeSources({'main.dart': _source});
    final path = '${directory.path}/main.dart';
    final official = await Process.run('$hostSdk/bin/dart', ['run', path]);
    expect(official.stdout, '2\n1\n', reason: '${official.stderr}');
    for (final host in Host.all) {
      for (final collectsAlways in [false, true]) {
        final program = '${directory.path}/program';
        writeProgram(
          await compileProgram(
            path,
            CompileOptions(target: host.target, collectsAlways: collectsAlways),
          ),
          program,
        );
        final run = await host.run(program);
        final reason = '${host.target}, collecting always: $collectsAlways';
        expect(run.output, official.stdout, reason: reason);
        expect(run.code, 0, reason: '$reason\n${run.errors}');
      }
    }
  }, skip: Host.missing);
}
