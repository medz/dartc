import 'package:dartc/lir.dart';

final _pair = LirSignature([.ref, .ref]);

/// Throws by searching the frames, as slowly as simply.
final LirFunction throwFunction = _throwing(isSwapped: false);

/// Like [throwFunction], with the exception and its trace swapped.
final LirFunction swappingThrowFunction = _throwing(isSwapped: true);

LirFunction _throwing({required bool isSwapped}) {
  final entry = LirBlock([.ref, .ref]);
  final frame = LirBlock([.i64]), search = LirBlock([.i64]);
  final test = LirBlock(), found = LirBlock();
  final [exception, trace] = entry.parameters;
  final code = entry.add(Convert(.ptrToInt, entry.add(SymbolAddress('.text'))));
  final table = entry.add(SymbolAddress(handlerSymbol));
  final count = entry.add(Load(.u32, table));
  entry.end(Jump(LirEdge(frame, [entry.add(FrameAddress())])));
  final at = frame.add(Convert(.intToPtr, frame.parameters.single));
  final returns = frame.add(Load(.i64, at, offset: 8));
  final offset = frame.add(IntBinary(.sub, returns, code));
  final caller = frame.add(Load(.i64, at));
  frame.end(Jump(LirEdge(search, [frame.add(ConstInt(0))])));
  final i = search.parameters.single;
  final more = search.add(Compare(.lt, i, count));
  search.end(Branch(more, LirEdge(test), LirEdge(frame, [caller])));
  final row = test.add(IntBinary(.mul, i, test.add(ConstInt(8))));
  final entryOffset = test.add(Load(.u32, table, offset: 4, index: row));
  final target = test.add(Load(.u32, table, offset: 8, index: row));
  final same = test.add(Compare(.eq, entryOffset, offset));
  final next = test.add(IntBinary(.add, i, test.add(ConstInt(1))));
  test.end(Branch(same, LirEdge(found), LirEdge(search, [next])));
  final pad = found.add(IntBinary(.add, code, target));
  found
    ..add(
      isSwapped
          ? Resume(caller, pad, trace, exception)
          : Resume(caller, pad, exception, trace),
    )
    ..end(Unreachable());
  return LirFunction(throwSymbol, _pair, [entry, frame, search, test, found]);
}

/// A function like [target] that gives [onThrow] where that throws.
LirFunction catching(
  String name,
  LirFunction target,
  LirValue Function(LirBlock handler, List<LirParameter> parameters) onThrow,
) {
  final signature = target.signature;
  final entry = LirBlock(signature.parameters);
  final normal = LirBlock([?signature.result]);
  final handler = LirBlock([.ref, .ref]);
  entry.end(
    Invoke(
      Call(target.name, signature, entry.parameters),
      LirEdge(normal),
      LirEdge(handler),
    ),
  );
  normal.end(Return(normal.parameters.firstOrNull));
  handler.end(Return(onThrow(handler, handler.parameters)));
  return LirFunction(name, signature, [entry, normal, handler]);
}
