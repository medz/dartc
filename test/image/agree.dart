import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A call to check, with its arguments.
typedef Case = ({String function, List<Object> arguments});

final callocExternal = LirExternal('calloc', LirSignature([.i64, .i64], .i64));

/// Allocates from the system and never collects.
final LirFunction allocateFunction = () {
  final block = LirBlock([.i64]);
  final one = block.add(ConstInt(1));
  final address = block.add(
    Call('calloc', callocExternal.signature, [one, block.parameters.single]),
  );
  block.end(Return(block.add(Convert(.intToRef, address))));
  return LirFunction('.allocate', LirSignature([.i64], .ref), [block]);
}();

const _limit = 250;

/// A program returning the 1-based number of the first case that differs from
/// [expected], or 0.
LirModule program(
  List<LirFunction> functions,
  List<Case> cases,
  List<int> expected, {
  List<LirData> data = const [],
  List<LirTable> tables = const [],
}) {
  final signatures = {for (final f in functions) f.name: f.signature};
  var block = LirBlock();
  final blocks = [block];
  for (final (i, (:function, :arguments)) in cases.indexed) {
    final call = block.add(
      Call(function, signatures[function]!, [
        for (final value in arguments)
          value is double
              ? block.add(ConstFloat(value))
              : block.add(ConstInt(value as int)),
      ]),
    );
    final same = block.add(
      Compare(.eq, call, block.add(ConstInt(expected[i]))),
    );
    final next = LirBlock(), failed = LirBlock();
    block.end(Branch(same, LirEdge(next), LirEdge(failed)));
    failed.end(Return(failed.add(ConstInt(i + 1))));
    blocks.addAll([failed, next]);
    block = next;
  }
  block.end(Return(block.add(ConstInt(0))));
  return LirModule(
    functions: [
      ...functions,
      allocateFunction,
      LirFunction('main', LirSignature([], .i64), blocks),
    ],
    externals: [callocExternal],
    data: data,
    tables: tables,
  );
}

/// Checks that machine code agrees with the interpreter on every case.
Future<void> agree(
  List<LirFunction> functions,
  List<Case> cases, {
  List<LirData> data = const [],
  List<LirTable> tables = const [],
}) async {
  for (var at = 0; at < cases.length; at += _limit) {
    final part = cases.skip(at).take(_limit).toList();
    final interpreter = LirInterpreter(
      LirModule(
        functions: [...functions, allocateFunction],
        externals: [callocExternal],
        data: data,
        tables: tables,
      ),
    );
    final expected = [
      for (final (:function, :arguments) in part)
        interpreter.call(function, arguments) as int,
    ];
    final code = await execute(
      program(functions, part, expected, data: data, tables: tables),
    );
    expect(
      code,
      0,
      reason: code > 0 ? 'differs: ${part[code - 1]}' : 'signal ${-code}',
    );
  }
}
