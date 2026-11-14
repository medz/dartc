/// Program analysis and bounded transformations for verified, immutable IR.
///
/// [reachableDefinitions] computes a conservative closure from explicit roots.
/// [CallTypeFlow] narrows virtual calls using argument and return facts. Extend
/// it only while its input program is unchanged, then hand [CallTypeFlow.facts]
/// to consumers. Rewritten IR requires a new analysis from the actual roots;
/// previous retained definitions are not additional entry points.
/// [inlineDirectCalls] expands small direct calls with bounded growth, preserving
/// effects and exceptional continuations while cleaning up the copied bodies.
///
/// @docImport 'src/optimizer/call_type_flow.dart';
/// @docImport 'src/optimizer/reachability.dart';
/// @docImport 'src/optimizer/inlining.dart';
library;

export 'src/optimizer/call_type_flow.dart' show CallTypeFlow, CallTypeFacts;
export 'src/optimizer/reachability.dart' show reachableDefinitions;
export 'src/optimizer/inlining.dart' show inlineDirectCalls;
