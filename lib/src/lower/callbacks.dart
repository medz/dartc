import 'package:dartc/lir.dart';
import 'package:dartc/native.dart';

import 'system.dart';
import 'system_calls.dart';

/// Where the thread that programs run on is.
const mainThreadSymbol = '.mainThread';

/// What functions of C that programs make do.
const callbackInfoSymbol = '.callbackInfo';

/// A lock and what waits for it to be signaled, and the first and the last of
/// the calls that are done later.
const _postedSymbol = '.posted';
const _mutex = 0, _condition = 64, _first = 128, _last = 136, _time = 144;
const _postedBytes = 160;

const postSymbol = '.post', takePostedSymbol = '.takePosted';
const waitPostedSymbol = '.waitPosted';

LirData mainThread() =>
    LirData(mainThreadSymbol, List.filled(8, 0), writable: true);

/// The data that calls from C need.
List<LirData> callbackData(SystemCalls system) => [
  LirData(
    callbackInfoSymbol,
    List.filled(Callbacks.count * Callbacks.infoBytes, 0),
    writable: true,
  ),
  LirData(_postedSymbol, [
    for (var i = 0; i < _postedBytes; i++)
      switch (i) {
        < 4 => system.mutexSignature >> i * 8 & 255,
        >= _condition && < _condition + 4 =>
          system.conditionSignature >> (i - _condition) * 8 & 255,
        _ => 0,
      },
  ], writable: true),
];

/// Remembers the thread at the start of the program.
void setMainThread(LirBlock block) {
  final thread = block.add(callSystem('pthread_self', []));
  block.add(Store(.i64, block.add(SymbolAddress(mainThreadSymbol)), thread));
}

/// The functions for calls from C, which the function [symbol] of [signature]
/// handles.
List<LirFunction> callbackFunctions(
  String symbol,
  LirSignature signature,
  SystemCalls system,
) => [_enter(symbol, signature), _post(), _take(), _wait(system)];

const _message = 'Cannot invoke native callback outside an isolate.\n';

/// Calls [symbol], which is of [handler], or has that done later.
LirFunction _enter(String symbol, LirSignature handler) {
  final signature = LirSignature([.i64, .ptr, .ptr]);
  final entry = LirBlock(signature.parameters);
  final [slot, block, stack] = entry.parameters;
  final later = LirBlock(), now = LirBlock(), here = LirBlock();
  final elsewhere = LirBlock();
  final done = LirBlock([?handler.result]);
  final failed = LirBlock([.ref, .ref]);
  final table = entry.add(SymbolAddress(callbackInfoSymbol));
  final three = entry.add(ConstInt(3));
  final at = entry.add(PtrAdd(table, entry.add(IntBinary(.shl, slot, three))));
  final info = entry.add(Load(.i64, at));
  final shift = entry.add(ConstInt(Callbacks.listenerBit));
  final bit = entry.add(IntBinary(.shr, info, shift));
  final isLater = entry.add(IntBinary(.and, bit, entry.add(ConstInt(1))));
  entry.end(Branch(isLater, LirEdge(later), LirEdge(now)));
  later
    ..add(
      Call(postSymbol, LirSignature([.i64, .i64, .ptr, .ptr]), [
        slot,
        info,
        block,
        stack,
      ]),
    )
    ..end(Return());
  final thread = now.add(callSystem('pthread_self', []));
  final main = now.add(Load(.i64, now.add(SymbolAddress(mainThreadSymbol))));
  final isMain = now.add(Compare(.eq, thread, main));
  now.end(Branch(isMain, LirEdge(here), LirEdge(elsewhere)));
  LirValue address(LirValue pointer) => here.add(Convert(.ptrToInt, pointer));
  final call = Call(symbol, handler, [slot, address(block), address(stack)]);
  here.end(Invoke(call, LirEdge(done), LirEdge(failed)));
  done.end(Return());
  // It catches everything itself.
  failed
    ..add(callSystem('abort', []))
    ..end(Unreachable());
  final text = elsewhere.add(SymbolAddress(callbackMessageSymbol));
  elsewhere
    ..add(
      callSystem('write', [
        elsewhere.add(ConstInt(2)),
        text,
        elsewhere.add(ConstInt(_message.length)),
      ]),
    )
    ..add(callSystem('abort', []))
    ..end(Unreachable());
  return LirFunction(callbackEntrySymbol, signature, [
    entry,
    later,
    now,
    here,
    elsewhere,
    done,
    failed,
  ]);
}

const callbackMessageSymbol = '.callbackMessage';
final callbackMessage = LirData(callbackMessageSymbol, _message.codeUnits);

LirValue _posted(LirBlock block, int offset) {
  final start = block.add(SymbolAddress(_postedSymbol));
  return block.add(PtrAdd(start, block.add(ConstInt(offset))));
}

void _lock(LirBlock block, {bool isOver = false}) => block.add(
  callSystem(isOver ? 'pthread_mutex_unlock' : 'pthread_mutex_lock', [
    _posted(block, _mutex),
  ]),
);

/// Copies a call to be done later, on any thread.
LirFunction _post() {
  final entry = LirBlock([.i64, .i64, .ptr, .ptr]);
  final [slot, info, block, stack] = entry.parameters;
  final low = entry.add(ConstInt(0xffffffff));
  final stackBytes = entry.add(IntBinary(.and, info, low));
  const own = Callbacks.postedBlock + CallBlock.stack;
  final size = entry.add(IntBinary(.add, stackBytes, entry.add(ConstInt(own))));
  final made = entry.add(callSystem('malloc', [size]));
  LirValue part(int offset) =>
      entry.add(PtrAdd(made, entry.add(ConstInt(offset))));
  final zero = entry.add(ConstInt(0));
  entry
    ..add(Store(.i64, made, zero))
    ..add(Store(.i64, made, slot, offset: Callbacks.postedSlot))
    ..add(Store(.i64, made, info, offset: Callbacks.postedInfo))
    ..add(
      callSystem('memcpy', [
        part(Callbacks.postedBlock),
        block,
        entry.add(ConstInt(CallBlock.stack)),
      ]),
    )
    ..add(callSystem('memcpy', [part(own), stack, stackBytes]));
  _lock(entry);
  final last = entry.add(Load(.ptr, _posted(entry, _last)));
  final some = LirBlock(), none = LirBlock(), done = LirBlock();
  final lastAddress = entry.add(Convert(.ptrToInt, last));
  entry.end(Branch(lastAddress, LirEdge(some), LirEdge(none)));
  some
    ..add(Store(.ptr, last, made))
    ..end(Jump(LirEdge(done)));
  none
    ..add(Store(.ptr, _posted(none, _first), made))
    ..end(Jump(LirEdge(done)));
  done.add(Store(.ptr, _posted(done, _last), made));
  done.add(callSystem('pthread_cond_signal', [_posted(done, _condition)]));
  _lock(done, isOver: true);
  done.end(Return());
  final signature = LirSignature([.i64, .i64, .ptr, .ptr]);
  return LirFunction(postSymbol, signature, [entry, some, none, done]);
}

/// Takes the first of the calls to be done later, if there are any.
LirFunction _take() {
  final entry = LirBlock(), some = LirBlock(), last = LirBlock();
  final done = LirBlock();
  _lock(entry);
  final first = entry.add(Load(.ptr, _posted(entry, _first)));
  final address = entry.add(Convert(.ptrToInt, first));
  entry.end(Branch(address, LirEdge(some), LirEdge(done)));
  final next = some.add(Load(.i64, first));
  some
    ..add(Store(.i64, _posted(some, _first), next))
    ..end(Branch(next, LirEdge(done), LirEdge(last)));
  last
    ..add(Store(.i64, _posted(last, _last), next))
    ..end(Jump(LirEdge(done)));
  _lock(done, isOver: true);
  done.end(Return(address));
  return LirFunction(takePostedSymbol, LirSignature([], .i64), [
    entry,
    some,
    last,
    done,
  ]);
}

/// Waits until there is a call to be done later, for some microseconds at most
/// unless that is negative.
LirFunction _wait(SystemCalls system) {
  final entry = LirBlock([.i64]), none = LirBlock(), long = LirBlock();
  final short = LirBlock(), done = LirBlock();
  _lock(entry);
  final first = entry.add(Load(.i64, _posted(entry, _first)));
  entry.end(Branch(first, LirEdge(done), LirEdge(none)));
  final time = entry.parameters.single;
  final isLong = none.add(Compare(.lt, time, none.add(ConstInt(0))));
  none.end(Branch(isLong, LirEdge(long), LirEdge(short)));
  long
    ..add(
      callSystem('pthread_cond_wait', [
        _posted(long, _condition),
        _posted(long, _mutex),
      ]),
    )
    ..end(Jump(LirEdge(done)));
  system.waitFor(
    short,
    _posted(short, _condition),
    _posted(short, _mutex),
    time,
    _posted(short, _time),
  );
  short.end(Jump(LirEdge(done)));
  _lock(done, isOver: true);
  done.end(Return());
  return LirFunction(waitPostedSymbol, LirSignature([.i64]), [
    entry,
    none,
    long,
    short,
    done,
  ]);
}
