import 'native_signature.dart';

/// An explicitly named native function, independent of its Dart declaration.
final class NativeExport(final String symbol, final NativeSignature signature) {
  this {
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(symbol) ||
        _keywords.contains(symbol)) {
      throw ArgumentError('Expected a non-reserved C identifier: $symbol');
    }
  }

  /// Writes a C prototype using exact-width integer types.
  void writeDeclaration(StringSink output) {
    final parameters = List.filled(signature.parameterCount, 'int64_t');
    output.writeln(
      'int64_t $symbol(${parameters.isEmpty ? 'void' : parameters.join(', ')});',
    );
  }
}

final _keywords = {
  ...('alignas alignof asm auto bool break case catch char char8_t char16_t char32_t '
          'class compl concept const consteval constexpr constinit const_cast continue '
          'co_await co_return co_yield decltype default delete do double dynamic_cast '
          'else enum explicit export extern false float for friend goto if inline int '
          'long mutable namespace new noexcept nullptr operator private protected public '
          'register reinterpret_cast requires restrict return short signed sizeof static '
          'static_assert static_cast struct switch template this thread_local throw true '
          'try typedef typeid typename typeof typeof_unqual union unsigned using virtual '
          'void volatile wchar_t while and and_eq bitand bitor not not_eq or or_eq xor xor_eq')
      .split(' '),
};
