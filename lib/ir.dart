/// Typed SSA values, functions and control-flow graphs.
///
/// Construct an [IrFunction] from finished blocks to verify the graph. Here a
/// [Jump] passes the argument to a second block, where [Return] reads it.
///
/// {@example /test/ir/graph_test.dart#block_arguments}
///
/// [IrProgram] checks references against the supplied class and callable
/// declarations. [IrExternal] describes a callable implemented outside the
/// graph using its Dart signature and defaults. Inspect [Instruction.effects]
/// for possible storage access, allocation, calls and exceptions.
///
/// @docImport 'src/ir/block.dart';
/// @docImport 'src/ir/function.dart';
/// @docImport 'src/ir/program.dart';
/// @docImport 'src/ir/value.dart';
library;

export 'src/ir/block.dart'
    show
        Await,
        Block,
        Branch,
        ExhaustivenessFailure,
        Invoke,
        Jump,
        Return,
        Terminator,
        Throw,
        Yield,
        YieldStream,
        Unreachable;
export 'src/ir/function.dart' show IrCallable, IrExternal, IrFunction;
export 'src/ir/program.dart' show IrClass, IrProgram;
export 'src/ir/ffi_types.dart' show FfiTypes;
export 'src/ir/signature.dart'
    show
        FunctionKind,
        FunctionBodyKind,
        FunctionTarget,
        DeferredImport,
        GlobalVariable,
        InstanceField,
        MemberSelector;
export 'src/ir/type.dart'
    show
        CellType,
        DynamicType,
        ClassType,
        FunctionType,
        FutureOrType,
        RecordType,
        ValueType,
        TypeParameterType,
        NonNullableTypeParameterType,
        PromotedTypeParameterType;
export 'src/ir/value.dart'
    show
        AwaitResult,
        LoadLibrary,
        CheckLibraryLoaded,
        TypeConstant,
        ReifyType,
        ObjectRuntimeType,
        ObjectHashCode,
        CollectionLength,
        CollectionGet,
        ListSet,
        ListSublist,
        MapContainsKey,
        MapEntries,
        PatternMatchFailure,
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
        NativeCall,
        DynamicDispatch,
        MakeInvocation,
        Equals,
        Effect,
        Instruction,
        PointerFromAddress,
        PointerAddress,
        PointerOffset,
        LoadNative,
        StoreNative,
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
        NumericToDouble,
        NumericToInt,
        NumericRoundToDouble,
        IntegerRounding,
        NumericSquareRoot,
        MakeClosure,
        MakeRecord,
        NewCell,
        ReadCell,
        LoadField,
        LoadGlobal,
        NullCheck,
        RecordConstant,
        SequenceConstant,
        MapConstant,
        ObjectConstant,
        RecordGet,
        ScalarConstant,
        StoreField,
        StoreGlobal,
        TestedValue,
        TypeCast,
        TypeView,
        TypeTest,
        UnwindValue,
        WriteCell,
        Value;

export 'src/ir/core_types.dart' show CoreTypes;
