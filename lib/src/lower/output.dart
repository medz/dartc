import 'dart:convert';

import 'package:dartc/lir.dart';

import 'system.dart';

/// Writes bytes to standard output, given their address and count.
const writeSymbol = '.write';
final writeSignature = LirSignature([.ptr, .i64]);

const _standardOutput = 1, _interrupted = 4, _brokenPipe = 13, _ignore = 1;

/// The texts a program prints, each stored once.
final class OutputData() {
  final _symbols = <String, String>{};
  final List<LirData> data = [];

  bool get isUsed => data.isNotEmpty;

  /// Adds a print of [text] to [block].
  void print(LirBlock block, String text) {
    final bytes = utf8.encode('$text\n');
    final symbol = _symbols.putIfAbsent(text, () {
      final name = '.text.${data.length}';
      data.add(LirData(name, bytes));
      return name;
    });
    final address = block.add(SymbolAddress(symbol));
    final count = block.add(ConstInt(bytes.length));
    block.add(Call(writeSymbol, writeSignature, [address, count]));
  }
}

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
  final entry = LirBlock([.ptr, .i64]), loop = LirBlock([.ptr, .i64]);
  final attempt = LirBlock(), advance = LirBlock(), failed = LirBlock();
  final done = LirBlock(), retry = LirBlock();
  entry.end(Jump(LirEdge(loop, entry.parameters)));
  final [address, count] = loop.parameters;
  loop.end(Branch(count, LirEdge(attempt), LirEdge(done)));
  final descriptor = attempt.add(ConstInt(_standardOutput));
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
