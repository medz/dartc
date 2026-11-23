import 'type_objects.dart';

/// What the runtime needs to know of the program it is part of.
///
/// Calls of the functions below go to functions made for each program.
/// Elsewhere they use [program].
abstract interface class Program() {
  RuntimeType typeOf(Object object);

  /// The object whose method [function] is, if it is one.
  Object? receiverOf(Object function);

  /// What else the text of [function] says.
  String functionName(Object function);

  /// The supertypes of a class, other than `Object`.
  SuperList? superTypesOf(int number);

  /// The number of the class `Function`.
  int get functionNumber;

  String className(int number);
  String parameterName(int number);
}

/// The program that the runtime is part of outside compiled programs.
late Program program;

RuntimeType typeOf(Object object) => program.typeOf(object);
Object? receiverOf(Object function) => program.receiverOf(function);
String functionName(Object function) => program.functionName(function);
SuperList? superTypesOf(int number) => program.superTypesOf(number);
int functionNumber() => program.functionNumber;
String className(int number) => program.className(number);
String parameterName(int number) => program.parameterName(number);
