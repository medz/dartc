import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'builtin_error.dart';
import 'captures.dart';
import 'classes.dart';
import 'closure.dart';
import 'constant_table.dart';
import 'dynamic_shape.dart';
import 'levels.dart';
import 'members.dart';

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

  /// Adds functions that are values.
  void addClosure(Closure closure);

  /// Adds the function of a closure, or of a variable's initializer.
  void addLocalFunction(HirFunction function);

  /// Adds the class of objects that are no values of the program.
  void addLocalClass(HirClass class_);

  /// The selector of calls of functions that are values.
  HirSelector callSelector(int positional, List<String> named);

  /// Whether objects are functions.
  HirTypeTest get functionTest;

  /// The object that [element] is, if the program declares it.
  HirConstObject? functionObject(ExecutableElement element);

  /// How to get the method [element] of objects of [receiver].
  HirSelector tearOffSelector(
    ExecutableElement element,
    InterfaceElement receiver,
  );

  /// Gives the method [found] of [receiver] itself.
  HirValue tearOff(
    FunctionBuilder builder,
    Implementation found,
    HirValue receiver,
  );

  /// Translates [body] as that of the function of [builder], later.
  void translateBody(FunctionBuilder builder, FunctionBody body);

  /// The value of [node] in the function of [builder], as one of [type].
  HirValue evaluate(FunctionBuilder builder, Expression node, DartType type);

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

  /// Where objects keep the type arguments of [level], if it has any.
  HirField? argumentsOf(Level level);

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

  /// The number telling that [BuiltinError.late] says [text].
  int lateNumber(String text);

  /// The class of stack traces.
  HirClass get traceClass;

  /// Tells that objects of [class_] are thrown.
  void addThrown(InterfaceElement class_);

  /// Whether objects are of [class_].
  HirTypeTest testOf(InterfaceElement class_);

  /// An instance member's own body at [level], taking the receiver first.
  HirFunction memberOf(Level level, ExecutableElement element);

  /// What [level] has for a member, called like a selector of
  /// [selectorOf]. Null if it is abstract there.
  HirFunction? functionAt(
    Level level,
    ExecutableElement member,
    int positional,
    List<String> named,
    Reject reject,
  );

  /// The level of [class_] itself.
  Level levelOf(ClassElement class_);

  /// A generative constructor's work on an object already created.
  HirFunction initializerOf(ConstructorElement element);

  /// A factory constructor.
  HirFunction factoryOf(ConstructorElement element);

  /// The class to create objects of.
  HirClass createdClass(ClassElement element);

  /// A field that [level] adds to objects, to be initialized.
  ///
  /// One that is `late` also tells whether that has been done.
  FieldPlace fieldOf(Level level, FieldElement element);

  /// Reads a field of [object], an object of [level].
  HirValue loadField(
    FunctionBuilder builder,
    Level level,
    FieldElement element,
    HirValue object,
  );

  /// Assigns [value] to a field of [object], an object of [level].
  void storeField(
    FunctionBuilder builder,
    Level level,
    FieldElement element,
    HirValue object,
    HirValue value,
  );

  /// How to call [member] on objects of [receiver], giving [positional]
  /// arguments and those [named], in alphabetical order.
  HirSelector selectorOf(
    ExecutableElement member,
    InterfaceElement receiver,
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
