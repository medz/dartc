/// Object header and descriptor encodings shared with runtime algorithms.
library;

export '../src/layout/memory_layout.dart'
    show
        ObjectHeader,
        ObjectDescriptor,
        RuntimeContext,
        ModuleRootTable,
        RuntimePhase,
        StackMapTable,
        StackMapRecord,
        SourceFrameMetadata,
        ClosureTraceMetadata;
