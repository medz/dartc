import 'package:dartc/lir.dart';

import 'runtime.dart';
import 'system.dart';
import 'system_calls.dart';

/// The function of C that runs an isolate other than the first on its thread.
const isolateEntrySymbol = '.isolateEntry';

/// Makes a copy of the data that each isolate has, as it is at the start.
const newIsolateSymbol = '.newIsolate';

/// Those bytes, which no isolate changes.
const _templateSymbol = '.isolateTemplate';

/// The function at [isolateEntrySymbol], which calls [spawned] with its
/// argument, the address of a word that has where the data of the isolate is.
/// Then it frees that and the word.
LirFunction isolateEntry(
  String spawned,
  LirSignature signature, {
  required bool checksStack,
  required SystemCalls system,
}) {
  final entry = LirBlock([.ptr]), done = LirBlock([?signature.result]);
  final failed = LirBlock([.ref, .ref]);
  final start = entry.parameters.single;
  if (checksStack) setStackLimit(entry, system);
  final call = Call(spawned, signature, [entry.add(Convert(.ptrToInt, start))]);
  entry.end(Invoke(call, LirEdge(done), LirEdge(failed)));
  final data = done.add(Load(.ptr, start));
  done
    ..add(callSystem('free', [start]))
    ..add(callSystem('free', [data]))
    ..end(Return(done.add(Convert(.intToPtr, done.add(ConstInt(0))))));
  // It catches everything itself.
  failed
    ..add(callSystem('abort', []))
    ..end(Unreachable());
  return LirFunction(
    isolateEntrySymbol,
    LirSignature([.ptr], .ptr),
    [entry, done, failed],
    isEntered: true,
    takesIsolate: true,
  );
}

/// The bytes of the data that each isolate has, at the start, among [data]
/// and [statics]; and the function at [newIsolateSymbol] that copies them.
({LirStatic template, LirFunction function}) isolateTemplate(
  Iterable<LirData> data,
  Iterable<LirStatic> statics,
) {
  final (:bytes, :references, offsets: _) = isolateData(data, statics);
  final entry = LirBlock(), copy = LirBlock(), done = LirBlock([.ptr]);
  final size = entry.add(ConstInt(bytes.length));
  final made = entry.add(callSystem('malloc', [size]));
  final address = entry.add(Convert(.ptrToInt, made));
  entry.end(Branch(address, LirEdge(copy), LirEdge(done, [made])));
  final from = copy.add(StaticObject(_templateSymbol));
  final start = copy.add(
    Convert(.intToPtr, copy.add(Convert(.refToInt, from))),
  );
  copy
    ..add(callSystem('memcpy', [made, start, size]))
    ..end(Jump(LirEdge(done, [made])));
  done.end(Return(done.add(Convert(.ptrToInt, done.parameters.single))));
  return (
    template: LirStatic(_templateSymbol, bytes, references: references),
    function: LirFunction(newIsolateSymbol, LirSignature([], .i64), [
      entry,
      copy,
      done,
    ]),
  );
}
