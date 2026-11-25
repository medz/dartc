// of SDK classes
int? ofSdkClasses() {
  return (double.infinity > double.maxFinite && double.nan != double.nan
      ? 1
      : 0);
}

// as divisors and shifts
int? asDivisorsAndShifts() {
  const n = 3;
  return 100 ~/ n % n << n;
}

void main() {
  print(ofSdkClasses()); // expect: 1
  print(asDivisorsAndShifts()); // expect: 0
}
