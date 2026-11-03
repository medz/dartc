/// Typed SSA values, functions and control-flow graphs.
library;

export 'src/ir/block.dart' show Block, Branch, Jump, Return, Terminator;
export 'src/ir/function.dart' show IrFunction;
export 'src/ir/signature.dart' show FunctionTarget, ValueType;
export 'src/ir/value.dart'
    show
        BlockParameter,
        Constant,
        DirectCall,
        Instruction,
        IntBinary,
        IntOperator,
        Value;
