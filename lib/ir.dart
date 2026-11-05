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
    show
        CellType,
        DynamicType,
        ClassType,
        FunctionType,
        RecordType,
        ValueType,
        TypeParameterType,
        NonNullableTypeParameterType,
        substituteType,
        typeParametersIn;
export 'src/ir/value.dart'
    show
        TypeConstant,
        ReifyType,
        ObjectHashCode,
        CollectionLength,
        CollectionGet,
        ListSet,
        ListSublist,
        MapContainsKey,
        MapEntries,
        PatternMatchFailure,
        coreCollectionOperation,
        NewCollection,
        CollectionAdd,
        CollectionSpread,
        MapPut,
        GetIterator,
        IteratorMoveNext,
        IteratorCurrent,
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
        InstantiateFunction,
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
        SequenceConstant,
        MapConstant,
        ObjectConstant,
        constantKey,
        RecordGet,
        ScalarConstant,
        StoreField,
        TestedValue,
        TypeCast,
        TypeView,
        TypeTest,
        UnwindValue,
        WriteCell,
        Value;

export 'src/ir/core_types.dart' show CoreTypes;
