/// Typed SSA values, functions and control-flow graphs.
///
/// Construct an [IrFunction] from finished blocks to verify the graph. Here a
/// [Jump] passes the argument to a second block, where [Return] reads it.
///
/// {@example /test/ir/graph_test.dart#block_arguments}
///
/// [IrProgram] checks references against the supplied class and callable
/// declarations. [IrExternal] describes a callable implemented outside the
/// graph using its Dart signature and defaults. [FunctionTarget.declarationLocation]
/// preserves the original declaration position, including part files.
/// [IrFunction.sourceLocations] associates instructions and terminating blocks
/// with source URIs and one-based line and column coordinates.
/// Inspect [Instruction.effects]
/// for possible storage access, allocation, calls and exceptions.
///
/// Generated [FunctionTarget] and [ClassType] definitions have a null library;
/// their names are labels, and references must use the original definition.
/// Source definitions retain their library URI. Private member selectors use
/// that URI or the declaring generated class as their scope.
///
/// @docImport 'src/ir/block.dart';
/// @docImport 'src/ir/function.dart';
/// @docImport 'src/ir/program.dart';
/// @docImport 'src/ir/signature.dart';
/// @docImport 'src/ir/type.dart';
/// @docImport 'src/ir/value.dart';
library;

export 'src/ir/dominance.dart' show ValueDominance;
export 'src/ir/origin.dart' show IrOrigin;
export 'src/ir/call_entry.dart' show CallEntryShape, CallEntryBinding;
export 'src/ir/member_entry.dart' show MemberEntryBinding;
export 'src/ir/cell_storage.dart' show CellStorage;
export 'src/ir/storage_view.dart' show StorageView;
export 'src/ir/callable_storage.dart' show CallableStorage, FunctionStorage;
export 'src/ir/type_binding.dart' show TypeBinding;
export 'src/ir/native_data.dart' show NativeData, NativeContextOwner;
export 'src/ir/execution_shape.dart'
    show ExecutionComponent, ExecutionShape, ExecutionSignature,
        ExecutionShapes, FunctionExecution, CaptureSlot;
export 'src/ir/native_boundary_bindings.dart'
    show NativeBoundaryBindings, NativeExportEntry, NativeImportEntry;
export 'src/ir/module_object.dart' show ModuleObject;
export 'src/ir/value_liveness.dart' show ValueLiveness;
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
export 'src/ir/function.dart'
    show
        IrCallable,
        IrExternal,
        IrFunction,
        ExternalMemory,
        ArbitraryMemory,
        UnchangedMemory,
        ZeroedMemory,
        WrittenMemory,
        ReleasedMemory,
        NativeResultMemory;
export 'src/ir/program.dart' show IrClass, IrProgram;
export 'src/ir/ffi_types.dart' show FfiTypes;
export 'src/ir/signature.dart'
    show
        FunctionKind,
        FunctionBodyKind,
        FunctionTarget,
        SourceLocation,
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
        PromotedType,
        PromotedTypeParameterType,
        InstantiatedPromotionType;
export 'src/ir/value.dart'
    show
        blockParameters,
        CaptureStackTrace,
        FrameValue,
        FrameValueKind,
        ReadNativeContext,
        BindNativeContext,
        CallFrameValue,
        ObjectDescriptorAddress,
        StackMapAddress,
        ModuleRootsAddress,
        InitializeObject,
        NativeCallbackTarget,
        StaticCallbackTarget,
        ClosureCallbackTarget,
        NativeCallbackAddress,
        NativeSymbolAddress,
        NativeDataAddress,
        FunctionEntryTableAddress,
        CellReference,
        InitializeStorageField,
        CellStorageView,
        CellStorageReference,
        CallableReference,
        ModuleObjectReference,
        NativeLocalStorage,
        AwaitResult,
        LoadLibrary,
        CheckLibraryLoaded,
        TypeConstant,
        ReifyType,
        CheckedTypeArgument,
        ObjectRuntimeType,
        ObjectHashCode,
        ObjectClassName,
        CollectionLength,
        CollectionGet,
        ListSet,
        ListSublist,
        MapContainsKey,
        MapEntries,
        PatternMatchFailure,
        NewCollection,
        ListFilled,
        ListFrom,
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
        RawNativeCall,
        DynamicDispatch,
        MakeInvocation,
        Equals,
        Identical,
        Effect,
        Instruction,
        ReferenceAddress,
        ReferenceFromAddress,
        AllocatedObject,
        ManagedStorageAllocation,
        NewPayload,
        NativeView,
        NativeAddress,
        NativeSize,
        NativeFieldOffset,
        CopyNative,
        KeepAlive,
        PointerFromAddress,
        PointerAddress,
        PointerOffset,
        LoadNative,
        LoadObjectData,
        StoreObjectData,
        LoadObjectReference,
        StoreObjectReference,
        StoreNative,
        FunctionCall,
        InstantiateFunction,
        FunctionConstant,
        InstanceCall,
        IntBinary,
        IntOperator,
        StringConcat,
        StringLength,
        StringFromCharCode,
        StringFromCharCodes,
        StringCodeUnitAt,
        NumericBinary,
        NumericOperator,
        NumericNegate,
        NumericToDouble,
        FloatBitCast,
        NumericToInt,
        NumericRoundToDouble,
        IntegerRounding,
        NumericSquareRoot,
        MakeClosure,
        ReadFunctionEnvironment,
        ReadFunctionTypeArgument,
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
        MaterializeValue,
        MaterializedValue,
        ConstantCarrier,
        ProjectValue,
        UncheckedCast,
        InstantiateFunctionFrom,
        TypeTest,
        UnwindValue,
        WriteCell,
        Value;

export 'src/ir/core_types.dart' show CoreTypes;

export 'src/ir/type_metadata.dart';
