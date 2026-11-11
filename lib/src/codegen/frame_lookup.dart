import 'dart:ffi';

import 'package:dartc/ir.dart';

/// Generates the shared return-PC lookup for stack roots and captured traces.
final class FrameLookup() {
  final target = FunctionTarget(
    Uri.parse('dartc:stack'),
    'findFrame',
    .integer,
    [.integer, .integer],
  );
  late final IrFunction function = _body();

  IrFunction _body() {
    Value load(Block block, Value base, [int offset = 0]) => block.emit(
      LoadNative(
        offset == 0
            ? base
            : block.emit(IntBinary(.add, base, Constant.integer(offset))),
        .new(Int64),
      ),
    );
    Value op(Block block, IntOperator operator, Value a, Value b) =>
        block.emit(IntBinary(operator, a, b));
    final entry = Block(target.parameterTypes);
    final loop = Block([.integer, .integer]);
    final candidate = Block(),
        next = Block(),
        found = Block(),
        missing = Block();
    final [table, pc] = entry.parameters;
    entry.finish(
      Jump(loop, [
        op(entry, .add, table, const Constant.integer(8)),
        load(entry, table),
      ]),
    );
    final [record, remaining] = loop.parameters;
    loop.finish(
      Branch(
        loop.emit(Equals(remaining, const Constant.integer(0))),
        Jump(missing),
        Jump(candidate),
      ),
    );
    candidate.finish(
      Branch(
        candidate.emit(Equals(load(candidate, record), pc)),
        Jump(found),
        Jump(next),
      ),
    );
    final bytes = op(
      next,
      .multiply,
      load(next, record, 24),
      const Constant.integer(8),
    );
    next.finish(
      Jump(loop, [
        op(
          next,
          .add,
          op(next, .add, record, bytes),
          const Constant.integer(32),
        ),
        op(next, .subtract, remaining, const Constant.integer(1)),
      ]),
    );
    found.finish(Return(record));
    missing.finish(Return(const Constant.integer(0)));
    return IrFunction(target, [entry, loop, candidate, next, found, missing]);
  }
}
