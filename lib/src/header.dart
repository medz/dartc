import 'diagnostic.dart';
import 'exports.dart';
import 'target.dart';
import 'types.dart';

bool _cIdentifier(String name) {
  if (name.isEmpty || name.startsWith('_') || name.startsWith('dartc_export_'))
    return false;
  for (var i = 0; i < name.length; i++) {
    final c = name.codeUnitAt(i);
    if (c != 95 &&
        !(c >= 65 && c <= 90) &&
        !(c >= 97 && c <= 122) &&
        !(i > 0 && c >= 48 && c <= 57))
      return false;
  }
  const reserved =
      '|alignas|alignof|and|and_eq|asm|auto|bitand|bitor|bool|break|case|catch|'
      'char|char8_t|char16_t|char32_t|class|compl|concept|const|consteval|'
      'constexpr|constinit|const_cast|continue|co_await|co_return|co_yield|'
      'decltype|default|delete|do|double|dynamic_cast|else|enum|explicit|'
      'export|extern|false|float|for|friend|goto|if|inline|int|long|mutable|'
      'namespace|new|noexcept|not|not_eq|nullptr|operator|or|or_eq|private|'
      'protected|public|register|reinterpret_cast|requires|restrict|return|'
      'short|signed|sizeof|static|static_assert|static_cast|struct|switch|'
      'template|this|thread_local|throw|true|try|typedef|typeid|typename|'
      'union|unsigned|using|virtual|void|volatile|wchar_t|while|xor|xor_eq|'
      '_Alignas|_Alignof|_Atomic|_Bool|_Complex|_Generic|_Imaginary|'
      '_Noreturn|_Static_assert|_Thread_local|NULL|'
      'int8_t|int16_t|int32_t|int64_t|uint8_t|uint16_t|uint32_t|uint64_t|'
      'int_least8_t|int_least16_t|int_least32_t|int_least64_t|'
      'uint_least8_t|uint_least16_t|uint_least32_t|uint_least64_t|'
      'int_fast8_t|int_fast16_t|int_fast32_t|int_fast64_t|'
      'uint_fast8_t|uint_fast16_t|uint_fast32_t|uint_fast64_t|'
      'intptr_t|uintptr_t|intmax_t|uintmax_t|size_t|ptrdiff_t|'
      'SIZE_MAX|PTRDIFF_MIN|PTRDIFF_MAX|SIG_ATOMIC_MIN|SIG_ATOMIC_MAX|'
      'WCHAR_MIN|WCHAR_MAX|WINT_MIN|WINT_MAX|';
  return reserved.indexOf('|' + name + '|') < 0 &&
      !name.startsWith('INT') &&
      !name.startsWith('UINT');
}

String _cName(String symbol) {
  if (_cIdentifier(symbol)) return symbol;
  const digits = '0123456789abcdef';
  var name = 'dartc_export_';
  for (var i = 0; i < symbol.length; i++) {
    final code = symbol.codeUnitAt(i);
    for (var shift = 12; shift >= 0; shift -= 4)
      name += digits[(code >> shift) & 15];
  }
  return name;
}

String _cString(String value) {
  var result = '"';
  const octal = '01234567';
  for (var i = 0; i < value.length; i++) {
    final code = value.codeUnitAt(i);
    if (code == 34 || code == 92) {
      result += '\\' + value[i];
    } else if (code < 32 || code == 127) {
      result +=
          '\\' +
          octal[(code >> 6) & 7] +
          octal[(code >> 3) & 7] +
          octal[code & 7];
    } else {
      result += value[i];
    }
  }
  return result + '"';
}

String _functionDeclaration(int type, String name) {
  final signature = functionSignature(type);
  var parameters = '';
  for (var i = 0; i < signature.parameters.length; i++) {
    if (i > 0) parameters += ', ';
    parameters += _declaration(signature.parameters[i], 'p' + i.toString());
  }
  if (parameters == '') parameters = 'void';
  return _declaration(signature.result, name + '(' + parameters + ')');
}

String _declaration(int type, String name, [bool constant = false]) {
  final kind = ffiKind(type);
  if (kind == ffiPointer)
    return _declaration(
      dartTypes[type].arguments[0],
      '*' + (constant ? ' const ' : '') + name,
    );
  if (kind == ffiNativeFunction)
    return _functionDeclaration(dartTypes[type].arguments[0], '(' + name + ')');
  final spelling = switch (kind) {
    ffiVoid => 'void',
    ffiInt8 => 'int8_t',
    ffiUint8 => 'uint8_t',
    ffiInt16 => 'int16_t',
    ffiUint16 => 'uint16_t',
    ffiInt32 => 'int32_t',
    ffiUint32 => 'uint32_t',
    ffiInt64 => 'int64_t',
    ffiUint64 => 'uint64_t',
    ffiIntPtr => 'intptr_t',
    ffiUintPtr => 'uintptr_t',
    ffiFloat => 'float',
    ffiDouble => 'double',
    ffiBool => 'bool',
    _ => throw Diagnostic(
      'dartc: C header generation for this FFI type is not implemented',
    ),
  };
  return (constant ? 'const ' : '') + spelling + ' ' + name;
}

String createCHeader() {
  var result =
      '#pragma once\n#include <stdint.h>\n#include <stdbool.h>\n\n'
      '#ifdef __cplusplus\nextern "C" {\n#endif\n\n';
  for (final declaration in checkedExports) {
    final name = _cName(declaration.symbol);
    result += 'extern ';
    if (declaration.function >= 0) {
      result += _functionDeclaration(declaration.signature, name);
    } else {
      result += _declaration(
        declaration.signature,
        name,
        declaration.constantBits != null,
      );
    }
    if (name != declaration.symbol) {
      final symbol = (targetOS == 0 ? '_' : '') + declaration.symbol;
      result += ' __asm__(' + _cString(symbol) + ')';
    }
    result += ';\n';
  }
  return result + '\n#ifdef __cplusplus\n}\n#endif\n';
}
