/// Typed SSA values, functions and control-flow graphs.
///
/// Construct an [IrFunction] from finished blocks to verify the graph. Here a
/// [Jump] passes the argument to a second block, where [Return] reads it.
///
/// {@example /test/ir/graph_test.dart#block_arguments}
///
/// @docImport 'src/ir/block.dart';
/// @docImport 'src/ir/function.dart';
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
