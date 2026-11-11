import 'package:dartc/ir.dart';

/// Builds checked numeric operations with ordinary control flow and exceptions.
final class NumericOperations({
  IrCallable? argumentError,
  IrCallable? unsupportedError,
}) {
  final IrCallable? _argumentError = argumentError;
  final IrCallable? _unsupportedError = unsupportedError;
  static final _uri = Uri.parse('dartc:numeric');
  final _functions = <IntOperator, IrFunction>{};
  final _quotients = <(ValueType, ValueType), IrFunction>{};
  final _conversions = <(IntegerRounding, bool), IrFunction>{};
  final _finiteConversions = <IntegerRounding, IrFunction>{};
  final _doubleRoundings = <(IntegerRounding, bool), IrFunction>{};
  final _nativeOperations = <Instruction>{};

  // Helper types must be available before their bodies are selected lazily.
  final classes = [IrClass(CoreTypes.integerDivisionByZeroException, [])];

  Iterable<IrFunction> get functions => _functions.values
      .followedBy(_quotients.values)
      .followedBy(_conversions.values)
      .followedBy(_finiteConversions.values)
      .followedBy(_doubleRoundings.values);

  FunctionTarget? callFor(Instruction instruction) {
    if (_nativeOperations.contains(instruction)) return null;
    if (instruction
        case IntBinary(
          operator: .shiftLeft || .shiftRight || .unsignedShiftRight,
          right: ScalarConstant(value: final int count),
        )
        when count >= 0 && count < 64) {
      return null;
    }
    if (instruction case NumericToInt(:final operand, :final rounding)) {
      return operand.type == .integer
          ? null
          : _conversion(rounding, operand.type == .floating).target;
    }
    if (instruction case NumericRoundToDouble(
      :final operand,
      :final rounding,
    )) {
      return operand.type == .integer
          ? null
          : _doubleRounding(rounding, operand.type == .floating).target;
    }
    if (instruction case NumericBinary(
      operator: .truncateDivide,
      :final left,
      :final right,
    )) {
      return _quotient(left.type, right.type).target;
    }
    final operator = _operator(instruction);
    return operator == null ? null : _function(operator).target;
  }

  static IntOperator? _operator(Instruction instruction) =>
      switch (instruction) {
        IntBinary(operator: final op)
            when op == .truncateDivide ||
                op == .modulo ||
                op == .remainder ||
                op == .shiftLeft ||
                op == .shiftRight ||
                op == .unsignedShiftRight =>
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

  IrFunction _quotient(ValueType leftType, ValueType rightType) {
    if (leftType != .integer && leftType != .floating) leftType = .number;
    if (rightType != .integer && rightType != .floating) rightType = .number;
    if (leftType == .integer && rightType == .integer) {
      return _function(.truncateDivide);
    }
    return _quotients.putIfAbsent((leftType, rightType), () {
      final target = FunctionTarget(
        _uri,
        'quotient.${leftType.dartName}.${rightType.dartName}',
        .integer,
        [leftType, rightType],
      );
      final entry = Block(target.parameterTypes);
      final [left, right] = entry.parameters;
      if (leftType != .number && rightType != .number) {
        final quotient = entry.emit(NumericBinary(.divide, left, right));
        entry.finish(
          Return(
            entry.emit(
              DirectCall(_conversion(.truncate, true).target, [quotient]),
            ),
          ),
        );
        return IrFunction(target, [entry]);
      }
      // Narrow boxed operands before selecting integer or floating arithmetic.
      final index = leftType == .number ? 0 : 1;
      final operand = entry.parameters[index];
      final integer = Block(), floating = Block();
      entry.finish(
        Branch(
          entry.emit(TypeTest(operand, .integer)),
          Jump(integer),
          Jump(floating),
        ),
      );
      for (final (block, type) in [
        (integer, ValueType.integer),
        (floating, ValueType.floating),
      ]) {
        final arguments = <Value>[...entry.parameters];
        arguments[index] = block.emit(TypeCast(operand, type));
        block.finish(
          Return(
            block.emit(
              DirectCall(
                _quotient(arguments[0].type, arguments[1].type).target,
                arguments,
              ),
            ),
          ),
        );
      }
      return IrFunction(target, [entry, integer, floating]);
    });
  }

  IrFunction _function(IntOperator operator) =>
      _functions.putIfAbsent(operator, () {
        final target = FunctionTarget(_uri, operator.name, .integer, [
          .integer,
          .integer,
        ]);
        if (operator == .shiftLeft ||
            operator == .shiftRight ||
            operator == .unsignedShiftRight) {
          return _shift(target, operator);
        }
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
        _nativeOperations.add(quotient);
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

  IrFunction _shift(FunctionTarget target, IntOperator operator) {
    final error = _argumentError;
    if (error == null) {
      throw UnsupportedError(
        'Integer shifts require the ArgumentError constructor body.',
      );
    }
    final entry = Block(target.parameterTypes);
    final [value, count] = entry.parameters;
    final valid = Block(),
        failed = Block(),
        large = Block(),
        shift = Block([.integer]);
    entry.finish(
      Branch(
        entry.emit(IntBinary(.lessThan, count, const Constant.integer(0))),
        Jump(failed),
        Jump(valid),
      ),
    );
    failed.finish(
      Throw(
        failed.emit(
          Construct(
            error.target,
            error.target.signature.bind<Value>(
              [count],
              {},
              (i) => error.defaults[i]!,
            ),
          ),
        ),
      ),
    );
    valid.finish(
      Branch(
        valid.emit(IntBinary(.lessThan, count, const Constant.integer(64))),
        Jump(shift, [count]),
        Jump(large),
      ),
    );
    large.finish(
      operator == .shiftRight
          ? Jump(shift, [const Constant.integer(63)])
          : const Return(Constant.integer(0)),
    );
    final result = shift.emit(
      IntBinary(operator, value, shift.parameters.single),
    );
    _nativeOperations.add(result);
    shift.finish(Return(result));
    return IrFunction(target, [entry, valid, failed, large, shift]);
  }

  IrFunction _conversion(
    IntegerRounding rounding,
    bool floating,
  ) => _conversions.putIfAbsent((rounding, floating), () {
    final target = FunctionTarget(
      _uri,
      '${rounding.name}${floating ? 'Double' : 'Num'}',
      .integer,
      [floating ? .floating : .number],
    );
    final entry = Block(target.parameterTypes);
    final value = entry.parameters.single;
    if (!floating) {
      final integer = Block(), other = Block();
      entry.finish(
        Branch(
          entry.emit(TypeTest(value, .integer)),
          Jump(integer),
          Jump(other),
        ),
      );
      integer.finish(Return(integer.emit(TypeCast(value, .integer))));
      other.finish(
        Return(
          other.emit(
            DirectCall(_conversion(rounding, true).target, [
              other.emit(TypeCast(value, .floating)),
            ]),
          ),
        ),
      );
      return IrFunction(target, [entry, integer, other]);
    }
    final error = _unsupportedError;
    if (error == null) {
      throw UnsupportedError(
        'Numeric conversions require the UnsupportedError constructor body.',
      );
    }
    final finite = Block(),
        upper = Block(),
        lower = Block(),
        high = Block(),
        low = Block(),
        convert = Block(),
        failed = Block();
    final blocks = [entry, finite, upper, lower, high, low, convert, failed];
    entry.finish(
      Branch(
        entry.emit(
          NumericBinary(
            .greaterOrEqual,
            value,
            const Constant.floating(-double.maxFinite),
          ),
        ),
        Jump(finite),
        Jump(failed),
      ),
    );
    finite.finish(
      Branch(
        finite.emit(
          NumericBinary(
            .lessOrEqual,
            value,
            const Constant.floating(double.maxFinite),
          ),
        ),
        Jump(upper),
        Jump(failed),
      ),
    );
    upper.finish(
      Branch(
        upper.emit(
          NumericBinary(
            .lessThan,
            value,
            const Constant.floating(9223372036854775808.0),
          ),
        ),
        Jump(lower),
        Jump(high),
      ),
    );
    lower.finish(
      Branch(
        lower.emit(
          NumericBinary(
            .greaterThan,
            value,
            const Constant.floating(-9223372036854775808.0),
          ),
        ),
        Jump(convert),
        Jump(low),
      ),
    );
    high.finish(const Return(Constant.integer(0x7fffffffffffffff)));
    low.finish(const Return(Constant.integer(-0x8000000000000000)));
    failed.finish(
      Throw(
        failed.emit(
          Construct(error.target, [
            const Constant.string('Infinity or NaN toInt'),
          ]),
        ),
      ),
    );
    convert.finish(
      Return(
        convert.emit(DirectCall(_finiteConversion(rounding).target, [value])),
      ),
    );
    return IrFunction(target, blocks);
  });

  // The caller proves a finite value strictly inside the signed integer range.
  IrFunction _finiteConversion(IntegerRounding rounding) =>
      _finiteConversions.putIfAbsent(rounding, () {
        final target = FunctionTarget(
          _uri,
          '${rounding.name}Finite',
          .integer,
          [.floating],
        );
        final convert = Block(target.parameterTypes);
        final value = convert.parameters.single;
        final blocks = [convert];
        final result = convert.emit(NumericToInt(value, .truncate));
        _nativeOperations.add(result);
        if (rounding == .truncate) {
          convert.finish(Return(result));
        } else {
          final fraction = convert.emit(
            NumericBinary(
              .subtract,
              value,
              convert.emit(NumericToDouble(result)),
            ),
          );
          final done = Block(), adjust = Block();
          blocks.addAll([done, adjust]);
          done.finish(Return(result));
          if (rounding == .round) {
            final negative = Block(), subtract = Block();
            blocks.addAll([negative, subtract]);
            convert.finish(
              Branch(
                convert.emit(
                  NumericBinary(
                    .greaterOrEqual,
                    fraction,
                    const Constant.floating(0.5),
                  ),
                ),
                Jump(adjust),
                Jump(negative),
              ),
            );
            negative.finish(
              Branch(
                negative.emit(
                  NumericBinary(
                    .lessOrEqual,
                    fraction,
                    const Constant.floating(-0.5),
                  ),
                ),
                Jump(subtract),
                Jump(done),
              ),
            );
            subtract.finish(
              Return(
                subtract.emit(
                  IntBinary(.subtract, result, const Constant.integer(1)),
                ),
              ),
            );
          } else {
            convert.finish(
              Branch(
                convert.emit(
                  NumericBinary(
                    rounding == .floor ? .lessThan : .greaterThan,
                    fraction,
                    const Constant.floating(0),
                  ),
                ),
                Jump(adjust),
                Jump(done),
              ),
            );
          }
          adjust.finish(
            Return(
              adjust.emit(
                IntBinary(
                  rounding == .floor ? .subtract : .add,
                  result,
                  const Constant.integer(1),
                ),
              ),
            ),
          );
        }
        return IrFunction(target, blocks);
      });

  IrFunction _doubleRounding(IntegerRounding rounding, bool floating) =>
      _doubleRoundings.putIfAbsent((rounding, floating), () {
        final target = FunctionTarget(
          _uri,
          '${rounding.name}ToDouble${floating ? 'Double' : 'Num'}',
          .floating,
          [floating ? .floating : .number],
        );
        final entry = Block(target.parameterTypes);
        final value = entry.parameters.single;
        if (!floating) {
          final integer = Block(), other = Block();
          entry.finish(
            Branch(
              entry.emit(TypeTest(value, .integer)),
              Jump(integer),
              Jump(other),
            ),
          );
          integer.finish(
            Return(
              integer.emit(
                NumericToDouble(integer.emit(TypeCast(value, .integer))),
              ),
            ),
          );
          other.finish(
            Return(
              other.emit(
                DirectCall(_doubleRounding(rounding, true).target, [
                  other.emit(TypeCast(value, .floating)),
                ]),
              ),
            ),
          );
          return IrFunction(target, [entry, integer, other]);
        }
        final upper = Block(),
            nonzero = Block(),
            unchanged = Block(),
            convert = Block(),
            zero = Block(),
            negativeZero = Block(),
            done = Block();
        // Doubles at or beyond 2^52 are integral; unordered comparisons preserve NaN.
        entry.finish(
          Branch(
            entry.emit(
              NumericBinary(
                .greaterThan,
                value,
                const Constant.floating(-4503599627370496.0),
              ),
            ),
            Jump(upper),
            Jump(unchanged),
          ),
        );
        upper.finish(
          Branch(
            upper.emit(
              NumericBinary(
                .lessThan,
                value,
                const Constant.floating(4503599627370496.0),
              ),
            ),
            Jump(nonzero),
            Jump(unchanged),
          ),
        );
        nonzero.finish(
          Branch(
            nonzero.emit(Equals(value, const Constant.floating(0))),
            Jump(unchanged),
            Jump(convert),
          ),
        );
        unchanged.finish(Return(value));
        final result = convert.emit(
          DirectCall(_finiteConversion(rounding).target, [value]),
        );
        convert.finish(
          Branch(
            convert.emit(Equals(result, const Constant.integer(0))),
            Jump(zero),
            Jump(done),
          ),
        );
        zero.finish(
          Branch(
            zero.emit(
              NumericBinary(.lessThan, value, const Constant.floating(0)),
            ),
            Jump(negativeZero),
            Jump(done),
          ),
        );
        negativeZero.finish(const Return(Constant.floating(-0.0)));
        done.finish(Return(done.emit(NumericToDouble(result))));
        return IrFunction(target, [
          entry,
          upper,
          nonzero,
          unchanged,
          convert,
          zero,
          negativeZero,
          done,
        ]);
      });
}
