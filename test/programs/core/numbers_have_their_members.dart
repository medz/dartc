void main() {
  for (final x in [
    0,
    1,
    -1,
    7,
    -7,
    255,
    9223372036854775807,
    -9223372036854775808,
    1 << 40,
  ]) {
    print(
      '$x ${x.hashCode} ${x.isEven} ${x.isOdd} ${x.abs()} ${x.sign} ${x.bitLength} ${x.toDouble()} ${x.toRadixString(16)} ${x.toRadixString(2)} ${~x} ${-x} ${x.compareTo(3)} ${x == 7.0} ${x.isNegative} ${x.toString().length} ${x.clamp(-3, 5)} ${x.remainder(4)} ${x ~/ 3} ${x % 3} ${x.toUnsigned(8)} ${x.toSigned(4)} ${x / 2} ${x.floor()} ${x.round()} ${x.truncate()} ${x.ceil()}',
    );
  }
  // expect: 0 0 true false 0 0 0 0.0 0 0 -1 0 -1 false false 1 0 0 0 0 0 0 0.0 0 0 0 0
  // expect: 1 11601 false true 1 1 1 1.0 1 1 -2 -1 -1 false false 1 1 1 0 1 1 1 0.5 1 1 1 1
  // expect: -1 0 false true 1 -1 0 -1.0 -1 -1 0 1 -1 false true 2 -1 -1 0 2 255 -1 -0.5 -1 -1 -1 -1
  // expect: 7 81207 false true 7 1 3 7.0 7 111 -8 -7 1 true false 1 5 3 2 1 7 7 3.5 7 7 7 7
  // expect: -7 69734 false true 7 -1 3 -7.0 -7 -111 6 7 -1 false true 2 -3 -3 -2 2 249 -7 -3.5 -7 -7 -7 -7
  // expect: 255 2958255 false true 255 1 8 255.0 ff 11111111 -256 -255 1 false false 3 5 3 85 0 255 -1 127.5 255 255 255 255
  // expect: 9223372036854775807 15352 false true 9223372036854775807 1 63 9223372036854776000.0 7fffffffffffffff 111111111111111111111111111111111111111111111111111111111111111 -9223372036854775808 -9223372036854775807 1 false false 19 5 3 3074457345618258602 1 255 -1 4611686018427388000.0 9223372036854775807 9223372036854775807 9223372036854775807 9223372036854775807
  // expect: -9223372036854775808 5800 true false -9223372036854775808 -1 63 -9223372036854776000.0 -8000000000000000 -1000000000000000000000000000000000000000000000000000000000000000 9223372036854775807 -9223372036854775808 -1 false true 20 -3 0 -3074457345618258602 1 0 0 -4611686018427388000.0 -9223372036854775808 -9223372036854775808 -9223372036854775808 -9223372036854775808
  // expect: 1099511627776 2969856 true false 1099511627776 1 41 1099511627776.0 10000000000 10000000000000000000000000000000000000000 -1099511627777 -1099511627776 1 false false 13 5 0 366503875925 1 0 0 549755813888.0 1099511627776 1099511627776 1099511627776 1099511627776
  print(12.gcd(18)); // expect: 6
  print(3.modPow(5, 7)); // expect: 5
  print(3.modInverse(7)); // expect: 5
  print(1 << 10 | 3); // expect: 1027
  print(int.parse('42') + int.parse('-7')); // expect: 35
  print(int.parse('ff', radix: 16)); // expect: 255
  print(int.parse('0x1F')); // expect: 31
  print(int.tryParse('x')); // expect: null
  print(int.tryParse('')); // expect: null
  print(int.tryParse('9223372036854775808')); // expect: null
  print(int.parse('-9223372036854775808')); // expect: -9223372036854775808
  num n = 5;
  print(n + 2.5); // expect: 7.5
  n = 2.5;
  print(n * 2); // expect: 5.0
  print(n.toInt()); // expect: 2
  print(n.compareTo(3)); // expect: -1
}
