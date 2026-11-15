/// Analysis and transformations of verified Dart programs.
///
/// [ProgramFlow] solves execution, values, calls and state for one immutable IR.
/// [ProgramOptimizer] applies semantic passes and recomputes facts after changes.
/// Supply actual invocations through [FlowEntry]; `openEntries`
/// describes callable boundaries whose arguments are externally unknown.
///
/// @docImport 'src/optimizer/program_flow.dart';
/// @docImport 'src/optimizer/program_optimizer.dart';
library;

export 'src/optimizer/call_type_flow.dart' show CallTypeFlow, CallTypeFacts;
export 'src/optimizer/reachability.dart' show reachableDefinitions;
export 'src/optimizer/flow_value.dart' show FlowValue, FlowObject, FlowAddress;
export 'src/optimizer/integer_range.dart' show FlowIntegerRange;
export 'src/optimizer/program_flow.dart'
    show ProgramFlow, ProgramFlowFacts, FlowEntry;
export 'src/optimizer/program_pass.dart' show ProgramPass, ProgramTransform;
export 'src/optimizer/program_optimizer.dart' show ProgramOptimizer;
export 'src/optimizer/simplification.dart' show ProgramSimplification;
export 'src/optimizer/inlining.dart' show DirectCallInlining;
export 'src/optimizer/loop_specialization.dart' show ProgramLoopSpecialization;
export 'src/optimizer/function_rewrite.dart' show FunctionRewrite;
export 'src/optimizer/storage_elimination.dart' show ProgramStorageElimination;
export 'src/optimizer/storage_promotion.dart' show ProgramStoragePromotion;
export 'src/optimizer/call_specialization.dart' show ProgramCallSpecialization;

export 'src/optimizer/memory_layout.dart' show FlowMemoryLayout;
