import 'package:dartc/lir.dart';
import 'package:test/test.dart';

void main() {
  test('prints every construct', () {
    final entry = LirBlock([.i64, .f64, .ref, .ptr]);
    final normal = LirBlock([.ref, .i64]), handler = LirBlock([.ref, .ref]);
    final dead = LirBlock(), end = LirBlock();
    final [i, f, r, p] = entry.parameters;
    final unary = LirSignature([.i64], .i64);
    entry
      ..add(ConstInt(-1))
      ..add(ConstFloat(0.5))
      ..add(ConstNull())
      ..add(SymbolAddress('d'))
      ..add(IntBinary(.add, i, i))
      ..add(FloatBinary(.mul, f, f))
      ..add(FloatUnary(.sqrt, f))
      ..add(Compare(.ult, i, i))
      ..add(Convert(.ptrToInt, p))
      ..add(PtrAdd(p, i))
      ..add(Load(.u8, p, offset: 4, index: i))
      ..add(Store(.ref, r, r, offset: 8))
      ..add(Call('g', unary, [i]))
      ..add(CallIndirect(p, unary, [i]))
      ..add(Alloc(i))
      ..end(Invoke(Alloc(i), LirEdge(normal, [i]), LirEdge(handler)));
    normal.end(Branch(i, LirEdge(dead), LirEdge(end)));
    handler.end(Throw(handler.parameters[0], handler.parameters[1]));
    dead.end(Unreachable());
    end.end(Return());
    final tail = LirBlock(), last = LirBlock();
    tail.end(Jump(LirEdge(last)));
    last.end(Return());
    final module = LirModule(
      functions: [
        LirFunction('f', LirSignature([.i64, .f64, .ref, .ptr]), [
          entry,
          normal,
          handler,
          dead,
          end,
        ]),
        LirFunction('t', LirSignature([]), [tail, last]),
      ],
      externals: [LirExternal('g', unary)],
      data: [
        LirData('d', [1, 2], writable: true),
      ],
    );
    verifyModule(module);
    expect(printModule(module), '''
data d: 2 bytes, writable
external g(i64) -> i64
func f(i64, f64, ref, ptr) {
b0(v0: i64, v1: f64, v2: ref, v3: ptr):
  v4 = int -1
  v5 = float 0.5
  v6 = null
  v7 = address d
  v8 = int.add v0, v0
  v9 = float.mul v1, v1
  v10 = float.sqrt v1
  v11 = i64.ult v0, v0
  v12 = ptrToInt v3
  v13 = ptr.add v3, v0
  v14 = load.u8 [v3 + v0 + 4]
  store.ref [v2 + 8], v2
  v15 = call g(v0)
  v16 = call v3 (i64) -> i64(v0)
  v17 = alloc v0
  invoke alloc v0, b1(v0), throw b2()
b1(v18: ref, v19: i64):
  branch v0, b3(), b4()
b2(v20: ref, v21: ref):
  throw v20, v21
b3():
  unreachable
b4():
  return
}
func t() {
b0():
  jump b1()
b1():
  return
}''');
  });

  test('prints a broken function without failing', () {
    final block = LirBlock()..add(Alloc(ConstInt(1)));
    final text = printFunction(LirFunction('f', LirSignature([]), [block]));
    expect(text, contains('alloc <undefined>'));
    expect(text, contains('<no terminator>'));
  });
}
