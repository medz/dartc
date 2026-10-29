import 'source.dart';
import 'symbols.dart';
import 'types.dart';

void declareFfiTypes(SymbolTable symbols) {
  const names = <String>[
    'Void',
    'Int8',
    'Uint8',
    'Int16',
    'Uint16',
    'Int32',
    'Uint32',
    'Int64',
    'Uint64',
    'IntPtr',
    'UintPtr',
    'Float',
    'Double',
    'Bool',
    'Pointer',
    'NativeFunction',
    'NativeType',
    'SizedNativeType',
    'Handle',
  ];
  for (var kind = 0; kind < names.length; kind++)
    declareSymbol(symbols, sourceFfi, names[kind], symbolType, ffiType(kind));
}

// A native marker is a Dart type, distinct from its ABI value representation.
int ffiDartType(int native, [bool result = false]) {
  final kind = ffiKind(native);
  if (kind == ffiVoid && result) return tVoid;
  if (kind >= ffiInt8 && kind <= ffiUintPtr) return tInt;
  if (kind == ffiFloat || kind == ffiDouble) return tDouble;
  if (kind == ffiBool) return tBool;
  if (kind == ffiPointer) return native;
  return -1;
}

bool ffiFunctionType(int type) {
  if (!typeIsFunction(type) || typeContainsParameters(type)) return false;
  final signature = functionSignature(type);
  if (signature.names.isNotEmpty ||
      signature.required != signature.parameters.length ||
      ffiDartType(signature.result, true) < 0)
    return false;
  for (final parameter in signature.parameters)
    if (ffiDartType(parameter) < 0 || !_ffiPointee(parameter)) return false;
  return _ffiPointee(signature.result);
}

bool _ffiPointee(int type) {
  final kind = ffiKind(type);
  if (kind == ffiNativeFunction)
    return ffiFunctionType(dartTypes[type].arguments[0]);
  if (kind == ffiPointer) return _ffiPointee(dartTypes[type].arguments[0]);
  return kind >= 0;
}
