import 'package:dartc/emit.dart';
import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import '../lir/support.dart';

void main() {
  void rejects(String what, LirModule module) => test('reports $what', () {
    expect(
      () => emitArm64(module),
      throwsA(
        isA<EmitUnsupported>().having((e) => '$e', 'text', contains(what)),
      ),
    );
  });

  rejects(
    'e: LirType.ref',
    LirModule(externals: [LirExternal('e', LirSignature([], .ref))]),
  );
  rejects('writable data', LirModule(data: [LirData('d', [], writable: true)]));

  LirModule ending(
    LirTerminator Function(LirBlock entry) end, [
    List<LirBlock> more = const [],
  ]) {
    final entry = LirBlock([.i64]);
    entry.end(end(entry));
    return LirModule(
      functions: [
        LirFunction('f', LirSignature([.i64]), [entry, ...more]),
        function('g', [], null, (_, _) => null),
      ],
    );
  }

  final normal = LirBlock()..end(Return());
  final handler = LirBlock([.ref, .ref])..end(Return());
  rejects(
    'Invoke',
    ending(
      (_) => Invoke(
        Call('g', LirSignature([]), []),
        LirEdge(normal),
        LirEdge(handler),
      ),
      [normal, handler],
    ),
  );

  test('refuses an invalid module', () {
    final module = LirModule(
      functions: [LirFunction('f', LirSignature([]), [])],
    );
    expect(() => emitArm64(module), throwsA(isA<LirError>()));
  });
}
