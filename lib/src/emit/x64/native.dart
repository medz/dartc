import 'package:dartc/lir.dart';
import 'package:dartc/native.dart';

import '../allocate.dart';
import '../backend.dart';
import 'assembler.dart';
import 'registers.dart';

const _rax = X64Assembler.rax, _rcx = X64Assembler.rcx;
const _rdx = X64Assembler.rdx, _rsp = X64Assembler.rsp;
const _rbp = X64Assembler.rbp, _rdi = X64Assembler.rdi;
const _rsi = X64Assembler.rsi, _r9 = X64Assembler.r9;
const _r10 = X64Assembler.r10, _r11 = X64Assembler.r11;

/// A register that calls keep, for the block.
const _block = X64Assembler.rbx;

final List<int> _words = x64Registers.arguments[RegisterBank.word]!;
final List<int> _floats = x64Registers.arguments[RegisterBank.float]!;
const _resultWords = [_rax, _rdx], _resultFloats = [0, 1];

Memory _inBlock(int base, int place, int index) =>
    Memory(base, offset: place + index * 8);

/// Emits the function that makes the call which a block describes.
///
/// It keeps the frame of the call before 8 bytes below its own, where the
/// collector finds it.
void emitNativeCall(X64Assembler assembler) {
  const kept = Memory(_rbp, offset: -16), before = Memory(_rbp, offset: -8);
  assembler
    ..push(_rbp)
    ..mov(_rbp, _rsp)
    ..subStack(16)
    ..store(_block, kept)
    ..mov(_block, _rdi)
    ..loadSymbol(_r10, nativeFrameSymbol)
    ..store(_r10, before)
    ..storeSymbol(_rbp, nativeFrameSymbol);
  _copyStack(assembler);
  for (final (i, register) in _words.indexed) {
    assembler.load(register, _inBlock(_block, CallBlock.words, i));
  }
  for (final (i, register) in _floats.indexed) {
    final from = _inBlock(_block, CallBlock.floats, i);
    assembler.load(register, from, float: true);
  }
  assembler
    ..load(_r11, const Memory(_block, offset: CallBlock.target))
    // How many doubles there may be, for variable arguments.
    ..constant(_rax, _floats.length)
    ..unary(.call, _r11);
  for (final (i, register) in _resultWords.indexed) {
    assembler.store(register, _inBlock(_block, CallBlock.resultWords, i));
  }
  for (final (i, register) in _resultFloats.indexed) {
    final to = _inBlock(_block, CallBlock.resultFloats, i);
    assembler.store(register, to, float: true);
  }
  assembler
    ..load(_r10, before)
    ..storeSymbol(_r10, nativeFrameSymbol)
    ..load(_block, kept)
    ..leave()
    ..ret();
}

/// Copies what is passed on the stack.
void _copyStack(X64Assembler assembler) {
  const bytes = _rcx, word = _r10;
  final loop = Label(), done = Label();
  assembler
    ..load(bytes, const Memory(_block, offset: CallBlock.stackBytes))
    ..binary(.sub, _rsp, bytes)
    ..bind(loop)
    ..binary(.test, bytes, bytes)
    ..jumpIf(.equal, done)
    ..load(
      word,
      const Memory(_block, offset: CallBlock.stack - 8, index: bytes),
    )
    ..store(word, const Memory(_rsp, offset: -8, index: bytes))
    ..lea(bytes, const Memory(bytes, offset: -8))
    ..jump(loop)
    ..bind(done);
}

/// Emits the functions of C that programs can make.
void emitCallbacks(X64Assembler assembler) {
  const number = _rax;
  final common = Label();
  for (var i = 0; i < Callbacks.count; i++) {
    final start = assembler.offset;
    assembler.callLabel(common);
    while (assembler.offset < start + Callbacks.entryBytes) {
      assembler.nop();
    }
  }
  // Where the call would return to tells which one it is.
  assembler
    ..bind(common)
    ..pop(number)
    ..address(_r11, callbacksSymbol)
    ..binary(.sub, number, _r11)
    ..shiftImmediate(.shr, number, 3);
  _enterBlock(assembler);
  assembler
    ..mov(_rdi, number)
    ..mov(_rsi, _rsp)
    // Above the saved frame and return addresses.
    ..lea(_rdx, const Memory(_rbp, offset: 16))
    ..call(callbackEntrySymbol);
  _leaveBlock(assembler);
}

/// Emits a function of C whose work [target] does.
void emitExport(X64Assembler assembler, String target) {
  _enterBlock(assembler);
  assembler
    ..mov(_rdi, _rsp)
    ..lea(_rsi, const Memory(_rbp, offset: 16))
    ..call(target);
  _leaveBlock(assembler);
}

/// Makes a frame with the block of a call, which has what is in registers.
void _enterBlock(X64Assembler assembler) {
  assembler
    ..push(_rbp)
    ..mov(_rbp, _rsp)
    ..subStack(CallBlock.stack);
  for (final (i, register) in _words.indexed) {
    assembler.store(register, _inBlock(_rsp, CallBlock.words, i));
  }
  for (final (i, register) in _floats.indexed) {
    final to = _inBlock(_rsp, CallBlock.floats, i);
    assembler.store(register, to, float: true);
  }
}

/// Returns with the results that the block has.
void _leaveBlock(X64Assembler assembler) {
  for (final (i, register) in _resultWords.indexed) {
    assembler.load(register, _inBlock(_rsp, CallBlock.resultWords, i));
  }
  for (final (i, register) in _resultFloats.indexed) {
    final from = _inBlock(_rsp, CallBlock.resultFloats, i);
    assembler.load(register, from, float: true);
  }
  assembler
    ..leave()
    ..ret();
}

/// Emits what Linux starts, where the stack has the program's arguments. It
/// runs [main].
void emitLinuxEntry(X64Assembler assembler, String main) => assembler
  ..constant(_rbp, 0)
  ..mov(_r9, _rdx)
  ..load(_rsi, const Memory(_rsp))
  ..lea(_rdx, const Memory(_rsp, offset: 8))
  ..mov(_rax, _rsp)
  ..alignStack()
  ..push(_rax)
  // The last argument, where the stack ends.
  ..push(_rax)
  ..address(_rdi, main)
  ..constant(_rcx, 0)
  ..constant(X64Assembler.r8, 0)
  ..call(linuxMainSymbol)
  ..breakpoint();
