import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'builtin_error.dart';
import 'captures.dart';
import 'closure.dart';
import 'constant_table.dart';
import 'dynamic_shape.dart';

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

  /// Which variables the closures in [declaration] use.
  Captures capturesOf(AstNode declaration);

  /// The class of the cells that closures share variables of [type] through.
  HirClass cellClass(HirType type);

  /// Adds what calls [function], which can be a value itself.
  void addClosure(
    Closure closure,
    HirFunction function, {
    required bool isValue,
  });

  /// The function of the local function [element].
  HirFunction localFunction(Element element);
  void setLocalFunction(Element element, HirFunction function);

  /// The selector of calls of functions that are values.
  HirSelector callSelector(int positional, List<String> named);

  /// Whether objects are functions.
  HirTypeTest get functionTest;

  /// The object that [element] is, if the program declares it.
  HirConstObject? functionObject(ExecutableElement element);

  /// How to get the method [element] of objects of [receiver].
  HirSelector tearOffSelector(ExecutableElement element, ClassElement receiver);

  /// Gives the method [element] of [receiver] itself.
  HirValue tearOff(
    FunctionBuilder builder,
    ExecutableElement element,
    HirValue receiver,
  );

  /// Translates [body] as that of the function of [builder], later.
  void translateBody(FunctionBuilder builder, FunctionBody body);

  /// The program's own element for [class_], which may be one of the SDK.
  InterfaceElement canonicalClass(InterfaceElement class_);

  /// A class of the runtime.
  ClassElement runtimeClass(String name);

  /// The class `Function`.
  ClassElement get functionClass;

  /// The object for [type], or null if it is generic.
  HirValue? typeValue(FunctionBuilder builder, DartType type);

  /// The type of the method [element] as a function, or null if it is generic.
  HirValue? methodType(FunctionBuilder builder, ExecutableElement element);

  /// The list of [types], or null if one of them is generic.
  HirValue? typeList(FunctionBuilder builder, List<DartType> types);

  /// The object for [types] if they are closed.
  Constant? constantTypes(List<DartType> types);

  /// Where objects keep the type arguments of [class_], if it is generic.
  HirField? argumentsOf(ClassElement class_);

  /// The function [element] with [types], or null if they are generic.
  HirValue? instantiate(
    FunctionBuilder builder,
    ExecutableElement element,
    List<DartType> types,
  );

  /// How to use members of objects of any class.
  HirSelector dynamicSelector(DynamicShape shape);

  /// A number for a member that is missing.
  int missingNumber(String kind, String name);

  /// Has [work] done later.
  void schedule(void Function() work);

  /// The class of the objects holding values of [type].
  HirClass boxClass(HirType type);

  /// The object that the constant [value] is.
  HirConstObject boxOf(Object value);

  /// A number for what is said about a value that is not of [type], which is
  /// null where it is known only when the program runs.
  int castNumber(String? type, String ending);

  /// The function called [name] in the runtime.
  HirFunction runtime(String name);

  /// A function that throws [error], given its number if it has one.
  HirFunction throwerOf(BuiltinError error);

  /// The number telling that [BuiltinError.late] is about the variable [name].
  int lateNumber(String name);

  /// The class of stack traces.
  HirClass get traceClass;

  /// Tells that objects of [class_] are thrown.
  void addThrown(ClassElement class_);

  /// Whether objects are of [class_].
  HirTypeTest testOf(ClassElement class_);

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

  /// The value of [node] as one of [type], which is checked if it is dynamic.
  HirValue valueTo(Expression node, DartType type);

  /// The value of [node], which must be represented as [type].
  HirValue valueAs(Expression node, HirType type);
}
