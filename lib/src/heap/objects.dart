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
