import 'package:dartc/lir.dart';
import 'package:dartc/native.dart';

import 'assembler.dart';

/// A register that calls keep, for the block.
const _block = 19;

const _scratch = 9, _from = 10, _to = 11, _word = 12, _function = 16;
const _saved = 16;

/// Emits the function that makes the call which a block describes.
///
/// It keeps the frame of the call before 8 bytes below its own, where the
/// collector finds it.
void emitNativeCall(Arm64Assembler assembler) {
  const frame = Arm64Assembler.frame, stack = Arm64Assembler.stack;
  assembler
    ..pushFrame()
    ..addImmediate(frame, stack, 0)
    ..constant(_scratch, _saved)
    ..subStack(_scratch)
    ..store(_block, stack, 0)
    ..mov(_block, 0)
    ..address(_scratch, nativeFrameSymbol)
    ..load(_word, _scratch, 0)
    ..store(_word, stack, 8)
    ..store(frame, _scratch, 0);
  _copyStack(assembler);
  for (var i = 0; i < 8; i++) {
    assembler
      ..load(i, _block, CallBlock.words + i * 8)
      ..load(i, _block, CallBlock.floats + i * 8, float: true);
  }
  assembler
    ..load(8, _block, CallBlock.resultAddress)
    ..load(_function, _block, CallBlock.target)
    ..callRegister(_function);
  for (var i = 0; i < 2; i++) {
    assembler.store(i, _block, CallBlock.resultWords + i * 8);
  }
  for (var i = 0; i < 4; i++) {
    assembler.store(i, _block, CallBlock.resultFloats + i * 8, float: true);
  }
  assembler
    // Back below the frame, where that of the call before is.
    ..constant(_scratch, _saved)
    ..sub(_scratch, frame, _scratch)
    ..addImmediate(stack, _scratch, 0)
    ..load(_word, stack, 8)
    ..address(_scratch, nativeFrameSymbol)
    ..store(_word, _scratch, 0)
    ..load(_block, stack, 0)
    ..addImmediate(stack, frame, 0)
    ..popFrame()
    ..ret();
}

/// Copies what is passed on the stack.
void _copyStack(Arm64Assembler assembler) {
  const stack = Arm64Assembler.stack, bytes = 13;
  final loop = Label(), done = Label();
  assembler
    ..load(bytes, _block, CallBlock.stackBytes)
    ..subStack(bytes)
    ..addImmediate(_to, stack, 0)
    ..addImmediate(_from, _block, CallBlock.stack)
    ..constant(_scratch, 8)
    ..bind(loop)
    ..jumpIfZero(bytes, done)
    ..load(_word, _from, 0)
    ..store(_word, _to, 0)
    ..addImmediate(_from, _from, 8)
    ..addImmediate(_to, _to, 8)
    ..sub(bytes, bytes, _scratch)
    ..jump(loop)
    ..bind(done);
}

/// Emits the functions of C that programs can make.
void emitCallbacks(Arm64Assembler assembler) {
  const frame = Arm64Assembler.frame, stack = Arm64Assembler.stack;
  const number = 16;
  final common = Label();
  for (var i = 0; i < Callbacks.count; i++) {
    assembler
      ..movz(number, i, 0)
      ..jump(common);
  }
  assembler.bind(common);
  _enterBlock(assembler);
  assembler
    ..mov(0, number)
    ..addImmediate(1, stack, 0)
    // Above the saved frame and return addresses.
    ..addImmediate(2, frame, 16)
    ..call(callbackEntrySymbol);
  _leaveBlock(assembler);
}

/// Emits a function of C whose work [target] does.
void emitExport(Arm64Assembler assembler, String target) {
  const frame = Arm64Assembler.frame, stack = Arm64Assembler.stack;
  _enterBlock(assembler);
  assembler
    ..addImmediate(0, stack, 0)
    ..addImmediate(1, frame, 16)
    ..call(target);
  _leaveBlock(assembler);
}

/// Makes a frame with the block of a call, which has what is in registers.
void _enterBlock(Arm64Assembler assembler) {
  const frame = Arm64Assembler.frame, stack = Arm64Assembler.stack;
  assembler
    ..pushFrame()
    ..addImmediate(frame, stack, 0)
    ..constant(_scratch, CallBlock.stack)
    ..subStack(_scratch);
  for (var i = 0; i < 8; i++) {
    assembler
      ..store(i, stack, CallBlock.words + i * 8)
      ..store(i, stack, CallBlock.floats + i * 8, float: true);
  }
  assembler.store(8, stack, CallBlock.resultAddress);
}

/// Returns with the results that the block has.
void _leaveBlock(Arm64Assembler assembler) {
  const frame = Arm64Assembler.frame, stack = Arm64Assembler.stack;
  for (var i = 0; i < 2; i++) {
    assembler.load(i, stack, CallBlock.resultWords + i * 8);
  }
  for (var i = 0; i < 4; i++) {
    assembler.load(i, stack, CallBlock.resultFloats + i * 8, float: true);
  }
  assembler
    ..addImmediate(stack, frame, 0)
    ..popFrame()
    ..ret();
}
