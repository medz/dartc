class const Box(final int value);
const value = Box((identical(1, 1.0) ? 1 : 'wrong') as dynamic);
