/// Generates native code from verified typed IR.
library;

export 'src/codegen/code_generator.dart' show CodeGenerator;
export 'src/codegen/arm64.dart' show Arm64CodeGenerator;
export 'src/codegen/x64.dart' show X64CodeGenerator;
