/// Generates native code from verified typed IR.
library;

export 'src/codegen/type_runtime.dart' show TypeRuntime;
export 'src/codegen/type_implementations.dart' show TypeImplementations;
export 'src/codegen/type_lowering.dart' show TypeLowering;
export 'src/codegen/callable_implementations.dart' show CallableImplementations;
export 'src/codegen/callable_lowering.dart' show CallableLowering;
export 'src/codegen/cell_lowering.dart' show CellLowering;
export 'src/codegen/member_entry_lowering.dart' show MemberEntryLowering;
export 'src/codegen/program_layout.dart'
    show ProgramLayout, ClassStorage, TypeTestKind;
export 'src/codegen/code_generator.dart' show CodeGenerator;
export 'src/codegen/program_normalization.dart' show ProgramNormalization;
export 'src/codegen/stack_trace_lowering.dart' show StackTraceLowering;
export 'src/codegen/allocation_lowering.dart' show AllocationLowering;
export 'src/codegen/representation_lowering.dart' show RepresentationLowering;
export 'src/codegen/global_lowering.dart' show GlobalLowering;
export 'src/codegen/constructor_tear_off_lowering.dart'
    show ConstructorTearOffLowering;
export 'src/codegen/suspension_normalization.dart' show SuspensionNormalization;
export 'src/codegen/native_boundaries.dart' show NativeBoundaries;
export 'src/codegen/native_call_lowering.dart' show NativeCallLowering;
export 'src/codegen/native_views.dart' show NativeViews;
export 'src/codegen/native_view_lowering.dart' show NativeViewLowering;
export 'src/codegen/program_preparation.dart'
    show ProgramPreparation, PreparedProgram;
export 'src/codegen/heap_runtime.dart'
    show
        HeapRuntime,
        MemoryPrimitive,
        AsyncRuntime,
        SyncRuntime,
        AsyncGeneratorRuntime;
export 'src/codegen/arm64.dart' show Arm64CodeGenerator;
export 'src/codegen/x64.dart' show X64CodeGenerator;
