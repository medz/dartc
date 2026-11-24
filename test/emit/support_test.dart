import 'package:dartc/emit.dart';
import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import '../lir/support.dart';

void main() {
  void rejects(String what, LirModule module) => test('reports $what', () {
    expect(
      () => emitCode(module),
      throwsA(
        isA<EmitUnsupported>().having((e) => '$e', 'text', contains(what)),
      ),
    );
  });

  rejects(
    'e: LirType.ref',
    LirModule(externals: [LirExternal('e', LirSignature([], .ref))]),
  );

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

  rejects(
    'f: no function .throw',
    ending((entry) {
      final none = entry.add(ConstNull());
      return Throw(none, none);
    }),
  );
  final normal = LirBlock([.ref])..end(Return());
  final handler = LirBlock([.ref, .ref])..end(Return());
  rejects(
    'f: no function .allocate',
    ending(
      (entry) => Invoke(
        Alloc(entry.parameters.single),
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
    expect(() => emitCode(module), throwsA(isA<LirError>()));
  });
}
