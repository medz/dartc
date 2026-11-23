import 'type_objects.dart';

/// What the runtime needs to know of the program it is part of.
///
/// Calls of the functions below go to functions made for each program.
/// Elsewhere they use [program].
abstract interface class Program() {
  RuntimeType typeOf(Object object);

  /// The supertypes of a class, other than `Object`.
  SuperList? superTypesOf(int number);

  /// The number of the class `Function`.
  int get functionNumber;

  /// Write names to standard error.
  void writeClassName(int number);
  void writeParameterName(int number);
  void writeBasicName(int kind);
  void writeRequired();
}

/// The program that the runtime is part of outside compiled programs.
late Program program;

RuntimeType typeOf(Object object) => program.typeOf(object);
SuperList? superTypesOf(int number) => program.superTypesOf(number);
int functionNumber() => program.functionNumber;
void writeClassName(int number) => program.writeClassName(number);
void writeParameterName(int number) => program.writeParameterName(number);
void writeBasicName(int kind) => program.writeBasicName(kind);
void writeRequired() => program.writeRequired();
