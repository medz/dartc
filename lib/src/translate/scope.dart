import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/native.dart';

import 'builder.dart';
import 'captures.dart';
import 'classes.dart';
import 'closure.dart';
import 'deferred_scope.dart';
import 'dynamic_shape.dart';
import 'levels.dart';
import 'members.dart';
import 'native_scope.dart';

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

  /// What the runtime's source calls the operation that calling [element]
  /// stands for, if it is one.
  String? operationOf(ExecutableElement element);

  /// Whether the program checks assertions.
  bool get checksAssertions;

  /// The class of objects that values of [type] are without boxes.
  ClassElement boxElement(HirType type);

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
  ///
  /// They give [types] type arguments first, if there are any.
  HirSelector callSelector(int types, int positional, List<String> named);

  /// How functions are called with a list of arguments and one of names.
  HirSelector get applySelector;

  /// The generic [function] with a list of type arguments and their number.
  HirValue partial(
    FunctionBuilder builder,
    HirValue function,
    (HirValue, int) types,
  );

  /// The object that [element], as a function of [type], is, if the program
  /// declares it.
  HirConstObject? functionObject(ExecutableElement element, FunctionType type);

  /// How to get the method [element] of objects of [receiver].
  HirSelector tearOffSelector(
    ExecutableElement element,
    InterfaceElement receiver,
  );

  /// Gives the method [found] of [receiver] itself, which may only be forwarded
  /// to its `noSuchMethod`.
  HirValue tearOff(
    FunctionBuilder builder,
    Implementation found,
    HirValue receiver, {
    bool isForwarder = false,
  });

  /// Gives the method [element] of an extension, used on [receiver], as a
  /// function. The extension has the type arguments [types], if any.
  HirValue extensionTearOff(
    FunctionBuilder builder,
    MethodElement element,
    HirValue receiver,
    HirValue? types,
  );

  /// Translates [body] as that of the function of [builder], which [coroutine]
  /// tells how to leave if it is not done at once.
  void translateBody(
    FunctionBuilder builder,
    FunctionBody body, [
    HirCoroutine? coroutine,
  ]);

  /// The value of [node] in the function of [builder], as one of [type].
  HirValue evaluate(FunctionBuilder builder, Expression node, DartType type);

  /// A class of the runtime.
  ClassElement runtimeClass(String name);

  /// The class `Function`.
  ClassElement get functionClass;

  /// Says that C calls the program.
  void addCallbacks();

  /// Says that collections have C do something.
  void addNativeFinalizers();

  /// The functions of C that the program calls.
  NativeScope get natives;

  /// The libraries that the program loads itself.
  DeferredScope get deferred;

  /// What the program is compiled for.
  Target get target;

  /// The class `Future`.
  ClassElement get futureClass;

  /// The function type called [name] in the runtime.
  FunctionType runtimeFunctionType(String name);

  /// The class of records.
  ClassElement get recordClass;

  /// A record of [values], of which the last have [names], in their order.
  HirValue record(
    FunctionBuilder builder,
    List<String> names,
    List<HirValue> values,
  );

  /// The list of the [names] of fields.
  HirInstruction names(List<String> names);

  /// The object for [type], or null if it is generic.
  HirValue? typeValue(FunctionBuilder builder, DartType type);

  /// The object that [type] is as a value, or null if it is not closed.
  HirConstObject? typeObject(DartType type);

  /// The runtime signature of a function or method taken as a value.
  HirValue? tearOffType(
    FunctionBuilder builder,
    ExecutableElement element, {
    FunctionType? asType,
    bool instanceMethod = false,
  });

  /// The list of [types], or null if one of them is generic.
  HirValue? typeList(FunctionBuilder builder, List<DartType> types);

  /// A list of [type] that holds [values] and does not grow.
  HirValue list(FunctionBuilder builder, DartType type, List<HirValue> values);

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

  /// What [selector], of those, does for null.
  HirFunction dynamicNull(HirSelector selector);

  /// The constant string [value].
  HirInstruction text(String value);

  /// Has [work] done later.
  void schedule(void Function() work);

  /// The class of the objects holding values of [type].
  HirClass boxClass(HirType type);

  /// The object that the constant [value] is.
  HirConstObject boxOf(Object value);

  /// The function called [name] in the runtime.
  HirFunction runtime(String name);

  /// The stack trace of what is thrown.
  HirInstruction get trace;

  /// Whether objects are of [class_].
  HirTypeTest testOf(InterfaceElement class_);

  /// Whether objects are of classes that extend `Error`.
  HirTypeTest get errorTest;

  /// An instance member's own body at [level], taking the receiver first.
  HirFunction memberOf(Level level, ExecutableElement element);

  /// Calls the `noSuchMethod` of objects of [level] for [element].
  HirFunction forwarderOf(Level level, ExecutableElement element);

  /// What [level] has for a member, called like a selector of
  /// [selectorOf]. Null if it is abstract there.
  HirFunction? functionAt(
    Level level,
    ExecutableElement member,
    int positional,
    List<String> named,
    Reject reject, {

    /// Whether the receiver may be taken as it is.
    bool isUnboxed = false,

    /// Whether to give a forwarder rather than null.
    bool orForwarder = false,
  });

  /// The level of [class_] itself.
  Level levelOf(InterfaceElement class_);

  /// A generative constructor's work on an object already created.
  HirFunction initializerOf(ConstructorElement element);

  /// A factory constructor.
  HirFunction factoryOf(ConstructorElement element);

  /// The class of objects that are of [level].
  HirClass classAt(Level level);

  /// Whether [class_] can be compiled.
  bool declares(InstanceElement class_);

  /// The class to create objects of.
  HirClass createdClass(InterfaceElement element);

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
    Reject reject, {
    required bool isOwn,
  });
}

/// Evaluates expressions of one function.
abstract interface class Evaluator() {
  /// Evaluates [node] without using its value.
  void effect(Expression node);

  /// The value of [node].
  ///
  /// An expression that never completes stands for a value of type
  /// [placeholder].
  HirValue value(Expression node, {HirType placeholder});

  /// The value of [node] as one of [type], which is checked if it is dynamic.
  HirValue valueTo(Expression node, DartType type);

  /// The value of [node], which must be represented as [type].
  HirValue valueAs(Expression node, HirType type);

  /// The value of [node] as one of [type], which is an object then.
  HirValue valueAsObject(Expression node, DartType type);
}
