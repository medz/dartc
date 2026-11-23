/// An error that the language itself throws, and what it says.
///
/// Constant ones are the same object every time.
enum BuiltinError(
  final String className,
  final String text, {
  final bool isConstant = false,

  /// Whether the text ends with a number, or depends on one.
  final bool hasNumber = false,

  /// Whether the text depends on an object.
  final bool hasObject = false,
}) {
  divisionByZero(
    'IntegerDivisionByZeroException',
    'IntegerDivisionByZeroException',
    isConstant: true,
  ),
  negativeShift('ArgumentError', 'Invalid argument(s): ', hasNumber: true),
  nullCheck('TypeError', 'Null check operator used on a null value'),

  /// A value is not of the type needed; the number says which.
  wrongType('TypeError', "type '", hasNumber: true, hasObject: true),
  missingMember(
    'NoSuchMethodError',
    'NoSuchMethodError: ',
    hasNumber: true,
    hasObject: true,
  ),
  noInt('UnsupportedError', 'Unsupported operation: Infinity or NaN toInt'),

  /// A `late` variable has no value, or one already; the number says which.
  late('Error', 'LateInitializationError: ', hasNumber: true),
  stackOverflow('StackOverflowError', 'Stack Overflow', isConstant: true),
  outOfMemory('OutOfMemoryError', 'Out of Memory', isConstant: true);

  /// Whether nothing more can be created when it is thrown.
  bool get isExhaustion => this == stackOverflow || this == outOfMemory;
}
