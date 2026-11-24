import 'package:dartc/lir.dart';

import 'system.dart';

/// Writes bytes to a descriptor, given their address and count.
const writeSymbol = '.write';
final writeSignature = LirSignature([.i64, .ptr, .i64]);

const _interrupted = 4, _brokenPipe = 13, _ignore = 1;

/// Where bytes are before they are written.
const bufferSymbol = '.buffer';
const bufferBytes = 4096;

/// Where calls of C functions are prepared.
const callBlockSymbol = '.callBlock';
final callNativeSignature = LirSignature([.ptr]);

/// Where the number of the program's arguments is, then their address.
const argumentsSymbol = '.arguments';
const argumentsBytes = 16;

/// Prepares output at the start of the program.
///
/// Like the official runtime, a program outlives the reader of its output.
void ignoreBrokenPipes(LirBlock block) => block.add(
  callSystem('signal', [
    block.add(ConstInt(_brokenPipe)),
    block.add(ConstInt(_ignore)),
  ]),
);

/// The function at [writeSymbol].
///
/// It continues after partial and interrupted writes. Any other error ends it,
/// as the official `print` ignores them.
LirFunction writeFunction() {
  final entry = LirBlock([.i64, .ptr, .i64]), loop = LirBlock([.ptr, .i64]);
  final attempt = LirBlock(), advance = LirBlock(), failed = LirBlock();
  final done = LirBlock(), retry = LirBlock();
  final [descriptor, ...bytes] = entry.parameters;
  entry.end(Jump(LirEdge(loop, bytes)));
  final [address, count] = loop.parameters;
  loop.end(Branch(count, LirEdge(attempt), LirEdge(done)));
  final written = attempt.add(
    callSystem('write', [descriptor, address, count]),
  );
  final zero = attempt.add(ConstInt(0));
  final progress = attempt.add(Compare(.gt, written, zero));
  attempt.end(Branch(progress, LirEdge(advance), LirEdge(failed)));
  final next = advance.add(PtrAdd(address, written));
  final rest = advance.add(IntBinary(.sub, count, written));
  advance.end(Jump(LirEdge(loop, [next, rest])));
  final negative = failed.add(Compare(.lt, written, zero));
  failed.end(Branch(negative, LirEdge(retry), LirEdge(done)));
  final error = retry.add(Load(.i32, retry.add(callSystem('__error', []))));
  final interrupted = retry.add(
    Compare(.eq, error, retry.add(ConstInt(_interrupted))),
  );
  retry.end(Branch(interrupted, LirEdge(loop, loop.parameters), LirEdge(done)));
  done.end(Return());
  return LirFunction(writeSymbol, writeSignature, [
    entry,
    loop,
    attempt,
    advance,
    failed,
    retry,
    done,
  ]);
}
