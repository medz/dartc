/// Value storage and object layouts for 64-bit Dart targets.
library;

export 'src/layout/memory_layout.dart'
    show
        ObjectHeader,
        ObjectDescriptor,
        RuntimeContext,
        StackMapTable,
        StackMapRecord,
        ClosureTraceMetadata;
export 'src/layout/object_layout.dart' show ObjectLayout, ValueRepresentation;
export 'src/layout/stack_roots.dart' show StackRoots;
