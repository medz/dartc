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

export 'src/ir/block.dart'
    show
        Block,
        Branch,
        ExhaustivenessFailure,
        Invoke,
        Jump,
        Return,
        Terminator,
        Throw,
        Unreachable;
export 'src/ir/function.dart' show IrFunction;
export 'src/ir/signature.dart' show FunctionTarget;
export 'src/ir/type.dart' show RecordType, ValueType;
export 'src/ir/value.dart'
    show
        BlockParameter,
        Constant,
        DirectCall,
        Equals,
        Instruction,
        IntBinary,
        IntOperator,
        MakeRecord,
        NullCheck,
        RecordConstant,
        RecordGet,
        ScalarConstant,
        TestedValue,
        TypeCast,
        TypeTest,
        UnwindValue,
        Value;
