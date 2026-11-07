#include <stdint.h>

int64_t first(void);
int64_t second(void);

int main(void) {
  return first() == 40 && second() == 2 ? 0 : 1;
}
