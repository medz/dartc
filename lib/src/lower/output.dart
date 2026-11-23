import 'dart:convert';

import 'package:dartc/lir.dart';

import 'system.dart';

/// Writes bytes to a descriptor, given their address and count.
const writeSymbol = '.write';
final writeSignature = LirSignature([.i64, .ptr, .i64]);

const standardOutput = 1, standardError = 2;
const _interrupted = 4, _brokenPipe = 13, _ignore = 1;

/// The texts a program prints, each stored once.
final class OutputData() {
  final _symbols = <String, String>{};
  final List<LirData> data = [];

  /// Every byte, so that each has an address.
  static const _bytes = '.bytes';
  bool _hasBytes = false;

  bool get isUsed => data.isNotEmpty;

  /// Adds a write of [text] to [block].
  void write(LirBlock block, int descriptor, String text) {
    final bytes = utf8.encode(text);
    final symbol = _symbols.putIfAbsent(text, () {
      final name = '.text.${data.length}';
      data.add(LirData(name, bytes));
      return name;
    });
    final address = block.add(SymbolAddress(symbol));
    _write(block, descriptor, address, bytes.length);
  }

  /// Adds a write of the single byte [value] to [block].
  void writeByte(LirBlock block, int descriptor, LirValue value) {
    if (!_hasBytes) {
      data.add(LirData(_bytes, List.generate(256, (i) => i)));
      _hasBytes = true;
    }
    final mask = block.add(ConstInt(0xff));
    final index = block.add(IntBinary(.and, value, mask));
    final address = block.add(PtrAdd(block.add(SymbolAddress(_bytes)), index));
    _write(block, descriptor, address, 1);
  }

  void _write(LirBlock block, int descriptor, LirValue address, int count) {
    final to = block.add(ConstInt(descriptor));
    final size = block.add(ConstInt(count));
    block.add(Call(writeSymbol, writeSignature, [to, address, size]));
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
