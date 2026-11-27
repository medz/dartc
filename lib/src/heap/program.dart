import 'type_objects.dart';

/// What the runtime needs to know of the program it is part of.
///
/// Calls of the functions below go to functions made for each program.
/// Elsewhere they use [program].
abstract interface class Program() {
  RuntimeType typeOf(Object object);

  /// The object whose method [function] is, or the generic function that it is
  /// with type arguments, if it is one. Other functions give themselves, or null
  /// if they have type arguments.
  Object? receiverOf(Object function);

  /// The types that [function] has been given, if it is generic.
  TypeList? typesOf(Object function);

  /// What else the text of [function] says.
  String functionName(Object function);

  /// What [function] is called where it is not given what it needs.
  String calledName(Object function);

  /// The supertypes of a class, other than `Object`.
  SuperList? superTypesOf(int number);

  /// The number of the class `Function`.
  int get functionNumber;

  /// The number of the class `Record`.
  int get recordNumber;

  /// The number of the class `Future`.
  int get futureNumber;

  String className(int number);

  /// Does what has to be done after each collection.
  void afterCollection();
}

/// The program that the runtime is part of outside compiled programs.
late Program program;

RuntimeType typeOf(Object object) => program.typeOf(object);
Object? receiverOf(Object function) => program.receiverOf(function);
TypeList? typesOf(Object function) => program.typesOf(function);
String functionName(Object function) => program.functionName(function);
String calledName(Object function) => program.calledName(function);
SuperList? superTypesOf(int number) => program.superTypesOf(number);
int functionNumber() => program.functionNumber;
int futureNumber() => program.futureNumber;
int recordNumber() => program.recordNumber;
String className(int number) => program.className(number);
void afterCollection() => program.afterCollection();
