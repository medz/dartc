/// Native integer entry points implemented with architecture encoding APIs.
library;

export 'src/abi/calling_convention.dart' show CallingConvention;
export 'src/abi/call_layout.dart' show CallLayout;
export 'src/abi/argument_location.dart'
    show
        ArgumentLocation,
        RegisterArgument,
        StackArgument,
        RegisterPart,
        RegisterAggregate,
        IndirectArgument;
export 'src/abi/frame_layout.dart' show FrameLayout;
export 'src/abi/arm64.dart' show Arm64Abi;
export 'src/abi/x64.dart' show X64Abi;
export 'src/abi/native_symbols.dart' show NativeSymbols;
export 'src/abi/native_layout.dart' show NativeLayout, NativeStorage;
