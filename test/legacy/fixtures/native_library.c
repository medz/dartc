#include "native_library.h"
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <string.h>
#include <stdio.h>
#include <dlfcn.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "failed line %d: %s\n", __LINE__, #x); return __LINE__; } } while (0)
static int64_t increment(int64_t value) { return value + 1; }
int main(void) {
CHECK(words(-128,255,-32768,65535,INT32_MIN,UINT32_MAX,-7,9) == INT64_C(15032549771));
CHECK(mixed(1.25,2.5f,-3,60000) == 239997.25);
CHECK(small_result(1) == 3);
CHECK(u32_result(0) == UINT32_MAX);
CHECK(i32_result(INT64_C(4294967295)) == -1);
CHECK(boolean(true, 5));
CHECK(!boolean(true, -1));
CHECK(!boolean(false, 0));
int8_t data = -5; CHECK(pointer(&data) == &data);
nothing();
CHECK(recurse(1.25f, 4) == 3.25f);
CHECK(internal_call(2.0) == 3.5);
CHECK(packed(1, 1.25, 2, 2.25, 3, 3.25, 4, 4.25, 5, 5.25, 6, 6.25, 7, 7.25, 8, 8.25, -100, 200, -30000, 60000, -1000000000, 3000000000u, 1.5f, 2.75, true, -99) == 45000630249.5);
CHECK(i8 == 1);
CHECK(u8 == UINT8_MAX);
CHECK(i16 == -1);
CHECK(u16 == UINT16_MAX);
CHECK(i32 == 1);
CHECK(u32 == UINT32_MAX);
CHECK(i64 == INT64_MIN);
CHECK(u64 == UINT64_MAX);
CHECK(b == true);
CHECK(double_value == 3.141592653589793);
{ float expected = (float)0.0; CHECK(memcmp(&f0, &expected, 4) == 0); }
{ float expected = (float)-0.0; CHECK(memcmp(&f1, &expected, 4) == 0); }
{ float expected = (float)3.141592653589793; CHECK(memcmp(&f2, &expected, 4) == 0); }
{ float expected = (float)1.000000059604644775390625; CHECK(memcmp(&f3, &expected, 4) == 0); }
{ float expected = (float)1.000000178813934326171875; CHECK(memcmp(&f4, &expected, 4) == 0); }
{ float expected = (float)1.1754943508222875e-38; CHECK(memcmp(&f5, &expected, 4) == 0); }
{ float expected = (float)1.1754942807573643e-38; CHECK(memcmp(&f6, &expected, 4) == 0); }
{ float expected = (float)1.401298464324817e-45; CHECK(memcmp(&f7, &expected, 4) == 0); }
{ float expected = (float)7.006492321624085e-46; CHECK(memcmp(&f8, &expected, 4) == 0); }
{ float expected = (float)7.006492321624086e-46; CHECK(memcmp(&f9, &expected, 4) == 0); }
{ float expected = (float)3.4028234663852886e38; CHECK(memcmp(&f10, &expected, 4) == 0); }
{ float expected = (float)3.4028235677973366e38; CHECK(memcmp(&f11, &expected, 4) == 0); }
{ float expected = (float)1e300; CHECK(memcmp(&f12, &expected, 4) == 0); }
{ float expected = (float)-1e300; CHECK(memcmp(&f13, &expected, 4) == 0); }
{ float expected = (float)1e-300; CHECK(memcmp(&f14, &expected, 4) == 0); }
{ float expected = (float)-1e-300; CHECK(memcmp(&f15, &expected, 4) == 0); }
{ float expected = INFINITY; CHECK(memcmp(&positive_inf, &expected, 4) == 0); }
{ float expected = -INFINITY; CHECK(memcmp(&negative_inf, &expected, 4) == 0); }
CHECK(original() == 257);
CHECK(dartc_export_0063006c006100730073(40) == 41);
CHECK(dartc_export_52a0d83dde42(40) == 42);
CHECK(dartc_export_006d006100740068002e006100640064(40) == 43);
CHECK(dartc_export_0069006e0074005f006c006500610073007400330032005f0074 == 44);
CHECK(dartc_export_00530049005a0045005f004d00410058 == 45);
CHECK(dartc_export_00640061007200740063005f006500780070006f00720074005f00300030003600330030003000360063003000300036003100300030003700330030003000370033 == 46);
CHECK(callback(increment)(41) == 42);
int64_t item = 42; int64_t* item_pointer = &item; CHECK(**nested(&item_pointer) == 42);
return 0;
}
