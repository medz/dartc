import 'package:dartc/ir.dart';

/// Builds checked integer division and remainders with ordinary control flow.
final class IntegerArithmetic(Iterable<IrFunction> functions) {
  static final _uri = Uri.parse('dartc:integer');
  final _functions = <IntOperator, IrFunction>{};
  final _quotients = <Instruction>{};

  this {
    for (final function in functions) {
      for (final block in function.blocks) {
        for (final instruction in block.instructions) {
          if (_operator(instruction) case final operator?) _function(operator);
        }
      }
    }
  }

  List<IrClass> get classes => [
    if (_functions.isNotEmpty)
      IrClass(CoreTypes.integerDivisionByZeroException, []),
  ];

  Iterable<IrFunction> get functions => _functions.values;

  FunctionTarget? callFor(Instruction instruction) {
    if (_quotients.contains(instruction)) return null;
    final operator = _operator(instruction);
    return operator == null ? null : _function(operator).target;
  }

  static IntOperator? _operator(Instruction instruction) =>
      switch (instruction) {
        IntBinary(operator: final op)
            when op == .truncateDivide || op == .modulo || op == .remainder =>
          op,
        NumericBinary(:final operator, :final left, :final right)
            when left.type == .integer && right.type == .integer =>
          switch (operator) {
            .truncateDivide => .truncateDivide,
            .modulo => .modulo,
            .remainder => .remainder,
            _ => null,
          },
        _ => null,
      };

  IrFunction _function(IntOperator operator) =>
      _functions.putIfAbsent(operator, () {
        final target = FunctionTarget(_uri, operator.name, .integer, [
          .integer,
          .integer,
        ]);
        final entry = Block(target.parameterTypes);
        final [left, right] = entry.parameters;
        final nonzero = Block(),
            failed = Block(),
            negativeOne = Block(),
            divide = Block();
        final blocks = [entry, nonzero, failed, negativeOne, divide];
        entry.finish(
          Branch(
            entry.emit(Equals(right, const Constant.integer(0))),
            Jump(failed),
            Jump(nonzero),
          ),
        );
        failed.finish(
          Throw(ObjectConstant(CoreTypes.integerDivisionByZeroException, {})),
        );
        nonzero.finish(
          Branch(
            nonzero.emit(Equals(right, const Constant.integer(-1))),
            Jump(negativeOne),
            Jump(divide),
          ),
        );
        negativeOne.finish(
          Return(
            operator == .truncateDivide
                ? negativeOne.emit(
                    IntBinary(.subtract, const Constant.integer(0), left),
                  )
                : const Constant.integer(0),
          ),
        );
        final quotient = divide.emit(IntBinary(.truncateDivide, left, right));
        _quotients.add(quotient);
        if (operator == .truncateDivide) {
          divide.finish(Return(quotient));
        } else {
          final product = divide.emit(IntBinary(.multiply, quotient, right));
          final remainder = divide.emit(IntBinary(.subtract, left, product));
          if (operator == .remainder) {
            divide.finish(Return(remainder));
          } else {
            final done = Block(),
                adjust = Block(),
                add = Block(),
                subtract = Block();
            blocks.addAll([done, adjust, add, subtract]);
            divide.finish(
              Branch(
                divide.emit(
                  IntBinary(.lessThan, remainder, const Constant.integer(0)),
                ),
                Jump(adjust),
                Jump(done),
              ),
            );
            done.finish(Return(remainder));
            adjust.finish(
              Branch(
                adjust.emit(
                  IntBinary(.lessThan, right, const Constant.integer(0)),
                ),
                Jump(subtract),
                Jump(add),
              ),
            );
            add.finish(Return(add.emit(IntBinary(.add, remainder, right))));
            subtract.finish(
              Return(subtract.emit(IntBinary(.subtract, remainder, right))),
            );
          }
        }
        return IrFunction(target, blocks);
      });
}
