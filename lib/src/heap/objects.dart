// What the standard libraries need of objects. Calls of these functions become
// single operations in compiled programs.

/// An array of the class [T] with [length] elements.
external T newArray<T>(int length);

/// The number of elements of [array].
external int lengthOf(Object array);

/// Use the element at [index] of an array, or those bytes of it that start
/// there.
external Object? loadReference(Object array, int index);
external void storeReference(Object array, int index, Object? value);
external int loadInt8(Object array, int index);
external void storeInt8(Object array, int index, int value);
external int loadUint8(Object array, int index);
external void storeUint8(Object array, int index, int value);
external int loadInt16(Object array, int index);
external void storeInt16(Object array, int index, int value);
external int loadUint16(Object array, int index);
external void storeUint16(Object array, int index, int value);
external int loadInt32(Object array, int index);
external void storeInt32(Object array, int index, int value);
external int loadUint32(Object array, int index);
external void storeUint32(Object array, int index, int value);
external int loadInt64(Object array, int index);
external void storeInt64(Object array, int index, int value);
external double loadFloat32(Object array, int index);
external void storeFloat32(Object array, int index, double value);
external double loadFloat64(Object array, int index);
external void storeFloat64(Object array, int index, double value);

/// [value], which is a [T].
external T unsafeCast<T>(Object? value);

/// The number of a class of `dart:core`, and an array of one.
external int coreClassNumber(String name);
external T newCoreArray<T>(String name, int length);

external double intToFloat(int value);

/// [value], which is finite, as the nearest integer there is towards 0.
external int floatToInt(double value);
external int floatBits(double value);
external double bitsFloat(int bits);
external double squareRoot(double value);
external double sine(double value);
external double cosine(double value);
external double tangent(double value);
external double arcSine(double value);
external double arcCosine(double value);
external double arcTangent(double value);
external double exponential(double value);
external double logarithm(double value);
external double arcTangent2(double y, double x);
external double power(double base, double exponent);

/// Reads and writes memory at [address].
external int load16(int address);
external void store16(int address, int value);
external double loadSingle(int address);
external void storeSingle(int address, double value);
external double loadDouble(int address);
external void storeDouble(int address, double value);

/// Where the functions of C that the program can make are, and the words that
/// tell about them.
external int callbacks();
external int callbackInfo();

/// The first call from C to be done later, or 0.
external int takePosted();

/// Waits for such a call, for some microseconds at most unless that is negative.
external void waitPosted(int microseconds);

/// Lets the program wait for what [source], an `EventSource`, tells.
external void registerEvents(Object source);

/// Where the bytes of [typedData] are.
external int dataAddress(Object typedData);

/// Typed data of [length] elements at [address].
external T listAt<T>(int kind, int address, int length);

/// Nanoseconds since 1970, or since some time that never changes.
external int realTime();
external int steadyTime();

/// Finds out about the seconds since 1970 that are stored at [address], in the
/// place where the program runs. Then there is, after them, what the C function
/// `localtime_r` writes.
external void localTime(int address);

/// 32 random bits.
external int randomBits();

/// Where the number of the program's arguments is, then the address of those,
/// which are addresses of bytes that a 0 ends.
external int arguments();

/// Waits for [microseconds].
external void pause(int microseconds);

/// Whether [object] is of a class that extends `Error`, rather than implements
/// it.
external bool isSubclassOfError(Object object);

/// Calls [function] with [arguments], of which the first is itself and the last
/// have [names].
external Object? applyFunction(Object function, List arguments, List names);

/// The `Uri` of the directory that paths start at.
external Object currentUri();

/// Ends the program with [code].
external Never exit(int code);

/// Throws [exception] with [trace].
external Never throwWith(Object exception, Object trace);
