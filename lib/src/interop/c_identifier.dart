void checkCIdentifier(String name) {
  if (!isCIdentifier(name)) {
    throw ArgumentError('Expected a non-reserved C identifier: $name');
  }
}

bool isCIdentifier(String name) =>
    RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(name) &&
    !_keywords.contains(name);

final _keywords = {
  // The generated header includes stdint.h; C++ shares its typedef namespace.
  for (final prefix in ['int', 'uint']) ...{
    '${prefix}ptr_t',
    '${prefix}max_t',
    for (final width in [8, 16, 32, 64]) ...{
      '$prefix${width}_t',
      '${prefix}_least${width}_t',
      '${prefix}_fast${width}_t',
    },
  },
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
