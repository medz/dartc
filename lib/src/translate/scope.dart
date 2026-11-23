import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

/// Reports that something is not supported yet.
typedef Reject = Never Function(String what);

/// A top-level variable or static field.
///
/// One that code sets before its first use has a [getter] that does so unless
/// [isSet].
final class GlobalVariable(
  final HirGlobal global, [
  final HirGlobal? isSet,
  final HirFunction? getter,
]);

/// What translating one function needs to know of the whole program.
///
/// Asking for something makes it part of the program.
abstract interface class ProgramScope() {
  /// A top-level or static function, or null if the SDK declares it.
  HirFunction? functionOf(ExecutableElement element);

  /// The operation that calling [element] stands for, in the collector.
  HirMachineOp? machineOpOf(ExecutableElement element);

  /// A top-level variable or static field, or null if the program does not
  /// declare it.
  GlobalVariable? globalOf(PropertyInducingElement element);

  /// What gives the constant [object] as a value of [type], or null if that is
  /// not supported yet.
  HirInstruction? constantOf(HirType? type, DartObject? object);

  /// What gives the value that [parameter] has where a call leaves it out.
  HirInstruction defaultOf(FormalParameterElement parameter);

  /// An instance member's own body, taking the receiver first.
  HirFunction memberOf(ExecutableElement element);

  /// A generative constructor's work on an object already created.
  HirFunction initializerOf(ConstructorElement element);

  /// A factory constructor.
  HirFunction factoryOf(ConstructorElement element);

  /// The class to create objects of.
  HirClass createdClass(ClassElement element);

  HirField fieldOf(FieldElement element);

  /// How to call [member] on objects of [receiver], giving [positional]
  /// arguments and those [named], in alphabetical order.
  HirSelector selectorOf(
    ExecutableElement member,
    ClassElement receiver,
    int positional,
    List<String> named,
    Reject reject,
  );
}

/// Evaluates expressions of one function.
abstract interface class Evaluator() {
  /// The value of [node].
  ///
  /// An expression that never completes stands for a value of type
  /// [placeholder].
  HirValue value(Expression node, {HirType placeholder});

  /// The value of [node], which must be represented as [type].
  HirValue valueAs(Expression node, HirType type);
}
