#include <stdint.h>
#include <stdio.h>
#include "generated.h"

int main(void) {
  if (native_add(19, 23) != 42 || reverse(10, 3) != -7 ||
      twice(-21) != -42 || increment(INT64_MAX) != INT64_MIN ||
      literal() != INT64_C(0x123456789abcdef0) ||
      mixed(100, 2, 30, 4, 5, 7) != 122) {
    return 1;
  }
  puts("native functions: ok");
  return 0;
}
