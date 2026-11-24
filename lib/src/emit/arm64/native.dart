import 'package:dartc/lir.dart';
import 'package:dartc/native.dart';

import 'assembler.dart';

/// Registers that calls keep, for the block and for the frame of the call
/// before.
const _block = 19, _outer = 20;

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
    ..store(_outer, stack, 8)
    ..mov(_block, 0)
    ..address(_scratch, nativeFrameSymbol)
    ..load(_outer, _scratch, 0)
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
    ..address(_scratch, nativeFrameSymbol)
    ..store(_outer, _scratch, 0)
    // Back below the frame, where the registers are.
    ..constant(_scratch, _saved)
    ..sub(_scratch, frame, _scratch)
    ..addImmediate(stack, _scratch, 0)
    ..load(_block, stack, 0)
    ..load(_outer, stack, 8)
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
