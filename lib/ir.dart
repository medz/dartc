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
export 'src/ir/program.dart' show IrClass, IrProgram;
export 'src/ir/signature.dart'
    show FunctionKind, FunctionTarget, InstanceField, MemberSelector;
export 'src/ir/type.dart'
    show CellType, ClassType, FunctionType, RecordType, ValueType;
export 'src/ir/value.dart'
    show
        AssertionFailure,
        BindMethod,
        BlockParameter,
        Constant,
        Construct,
        CopyCell,
        DirectCall,
        Equals,
        Instruction,
        FunctionCall,
        FunctionConstant,
        InstanceCall,
        IntBinary,
        IntOperator,
        Interpolate,
        StringConcat,
        NumericBinary,
        NumericOperator,
        NumericNegate,
        MakeClosure,
        MakeRecord,
        NewCell,
        ReadCell,
        LoadField,
        NullCheck,
        RecordConstant,
        RecordGet,
        ScalarConstant,
        StoreField,
        TestedValue,
        TypeCast,
        TypeTest,
        UnwindValue,
        WriteCell,
        Value;
