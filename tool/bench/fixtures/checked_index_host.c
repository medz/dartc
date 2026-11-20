#include <stdbool.h>
#include <inttypes.h>
#include <stdio.h>

extern int64_t checkedIndex(int64_t index, bool enforce);

int main(void) {
    const int64_t accepted = checkedIndex(6, true);
    const int64_t caught = checkedIndex(-4, true);
    const int64_t skipped = checkedIndex(-4, false);
    printf("%" PRId64 " %" PRId64 " %" PRId64 "\n", accepted, caught, skipped);
    return accepted == 7 && caught == 81 && skipped == -4 ? 0 : 1;
}
