import 'package:dartc/lir.dart';

import 'callbacks.dart';
import 'runtime.dart';
import 'system.dart';
import 'system_calls.dart';

/// How many calls of functions that a library exports are running.
const _depthSymbol = '.depth';

const _enterSymbol = '.enter', _leaveSymbol = '.leave';

const _message = 'The library is used by another thread.\n';
const _messageSymbol = '.threadMessage';

/// What a library needs to be called.
List<LirData> exportData() => [
  LirData(_depthSymbol, List.filled(8, 0), writable: true, isolated: true),
  LirData(_messageSymbol, _message.codeUnits),
];

/// What handles what calls of exported functions throw.
typedef Uncaught = ({String symbol, LirSignature signature});

/// The functions that do the work of those that a library exports, of which
/// [handlers] tells what each calls, and the names of those.
({List<LirFunction> functions, Map<String, String> names}) exportFunctions(
  Map<String, ({String symbol, LirSignature signature})> handlers, {
  required Uncaught? uncaught,
  required ({String symbol, LirSignature signature})? eventLoop,
  required bool checksStack,
  required SystemCalls system,
}) {
  final names = <String, String>{};
  final functions = [
    _enter(system, checksStack: checksStack),
    _leave(eventLoop, uncaught),
  ];
  for (final MapEntry(key: name, value: handler) in handlers.entries) {
    final symbol = names[name] = '.export.${names.length}';
    functions.add(_export(symbol, handler, uncaught));
  }
  return (functions: functions, names: names);
}

LirFunction _export(
  String symbol,
  ({String symbol, LirSignature signature}) handler,
  Uncaught? uncaught,
) {
  final entry = LirBlock([.ptr, .ptr]);
  final done = LirBlock([?handler.signature.result]);
  entry.add(Call(_enterSymbol, LirSignature([]), const []));
  final call = Call(handler.symbol, handler.signature, [
    for (final parameter in entry.parameters)
      entry.add(Convert(.ptrToInt, parameter)),
  ]);
  final failed = _guard(entry, call, done, uncaught);
  done
    ..add(Call(_leaveSymbol, LirSignature([]), const []))
    ..end(Return());
  return LirFunction(symbol, LirSignature([.ptr, .ptr]), [
    entry,
    done,
    ...failed,
  ], isEntered: true);
}

/// Lets [block] end with [call], after which [done] follows. What it throws
/// ends the program. Returns the blocks for that.
List<LirBlock> _guard(
  LirBlock block,
  Call call,
  LirBlock done,
  Uncaught? uncaught,
) {
  if (uncaught == null) {
    // Nothing throws.
    final result = block.add(call);
    block.end(Jump(LirEdge(done, [if (call.type != null) result])));
    return const [];
  }
  final failed = LirBlock([.ref, .ref]);
  block.end(Invoke(call, LirEdge(done), LirEdge(failed)));
  failed
    ..add(Call(uncaught.symbol, uncaught.signature, failed.parameters))
    ..add(callSystem('abort', []))
    ..end(Unreachable());
  return [failed];
}

/// Prepares what depends on the thread, at the first of the calls that are
/// running. The others have to be on the same one.
LirFunction _enter(SystemCalls system, {required bool checksStack}) {
  final entry = LirBlock(), first = LirBlock(), other = LirBlock();
  final done = LirBlock(), wrong = LirBlock();
  final place = entry.add(SymbolAddress(_depthSymbol));
  final depth = entry.add(Load(.i64, place));
  final one = entry.add(ConstInt(1));
  entry
    ..add(Store(.i64, place, entry.add(IntBinary(.add, depth, one))))
    ..end(Branch(depth, LirEdge(other), LirEdge(first)));
  setMainThread(first);
  if (checksStack) setStackLimit(first, system);
  first.end(Jump(LirEdge(done)));
  final thread = other.add(callSystem('pthread_self', []));
  final main = other.add(
    Load(.i64, other.add(SymbolAddress(mainThreadSymbol))),
  );
  final isMain = other.add(Compare(.eq, thread, main));
  other.end(Branch(isMain, LirEdge(done), LirEdge(wrong)));
  wrong
    ..add(
      callSystem('write', [
        wrong.add(ConstInt(2)),
        wrong.add(SymbolAddress(_messageSymbol)),
        wrong.add(ConstInt(_message.length)),
      ]),
    )
    ..add(callSystem('abort', []))
    ..end(Unreachable());
  done.end(Return());
  return LirFunction(_enterSymbol, LirSignature([]), [
    entry,
    first,
    other,
    done,
    wrong,
  ]);
}

/// Does what was left to be done later, after the last of the calls that are
/// running.
LirFunction _leave(
  ({String symbol, LirSignature signature})? eventLoop,
  Uncaught? uncaught,
) {
  final entry = LirBlock(), last = LirBlock();
  final done = LirBlock([?eventLoop?.signature.result]), end = LirBlock();
  LirValue change(LirBlock block, IntOp op) {
    final place = block.add(SymbolAddress(_depthSymbol));
    final depth = block.add(Load(.i64, place));
    final changed = block.add(IntBinary(op, depth, block.add(ConstInt(1))));
    block.add(Store(.i64, place, changed));
    return changed;
  }

  if (eventLoop == null) {
    change(entry, .sub);
    entry.end(Return());
    return LirFunction(_leaveSymbol, LirSignature([]), [entry]);
  }
  final place = entry.add(SymbolAddress(_depthSymbol));
  final depth = entry.add(Load(.i64, place));
  final isLast = entry.add(Compare(.eq, depth, entry.add(ConstInt(1))));
  entry.end(Branch(isLast, LirEdge(last), LirEdge(end)));
  // The events may call exported functions again.
  final call = Call(eventLoop.symbol, eventLoop.signature, const []);
  final failed = _guard(last, call, done, uncaught);
  done.end(Jump(LirEdge(end)));
  change(end, .sub);
  end.end(Return());
  return LirFunction(_leaveSymbol, LirSignature([]), [
    entry,
    last,
    done,
    end,
    ...failed,
  ]);
}
