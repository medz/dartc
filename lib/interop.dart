/// Native bindings, export annotations, checked signatures and C declarations.
library;

export 'src/interop/annotation.dart' show Export;
export 'src/interop/native_export.dart' show NativeExport;
export 'src/interop/native_import.dart' show NativeImport;
export 'src/interop/native_reference.dart' show NativeReference;
export 'src/interop/exports.dart' show NativeExports;
export 'src/interop/native_signature.dart'
    show
        NativeSignature,
        NativeTypeRef,
        NativeScalarType,
        NativePointerType,
        NativeFunctionType,
        NativeField,
        NativeCompoundType,
        NativeArrayType,
        NativeOpaqueType;
export 'src/interop/native_type.dart' show NativeTypeLayout;
