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

  LirModule body(
    List<LirType> parameters,
    void Function(LirBlock block, List<LirParameter> p) build,
  ) => LirModule(
    functions: [
      function('f', parameters, null, (block, p) {
        build(block, p);
        return null;
      }),
    ],
  );

  rejects(
    'external',
    LirModule(externals: [LirExternal('e', LirSignature([]))]),
  );
  rejects('data', LirModule(data: [LirData('d', [])]));
  rejects('f64', body([.f64], (_, _) {}));
  rejects('ref', body([.ref], (_, _) {}));
  rejects('f64', body([], (block, _) => block.add(ConstFloat(1))));
  rejects('Load', body([.ptr], (block, p) => block.add(Load(.i64, p[0]))));
  rejects(
    'Store',
    body([.ptr, .i64], (block, p) {
      block.add(Store(.i64, p[0], p[1]));
    }),
  );
  rejects('ref', body([.i64], (block, p) => block.add(Alloc(p[0]))));

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
