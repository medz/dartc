void main() {
  final a = BigInt.parse('123456789012345678901234567890'),
      b = BigInt.from(987654321);
  print(a + b); // expect: 123456789012345678902222222211
  print(a * b); // expect: 121932631124828532112482853211126352690
  print(a ~/ b); // expect: 124999998873437499901
  print(a % b); // expect: 574845669
  print(-a); // expect: -123456789012345678901234567890
  print(a.pow(3)); // expect: 1881676372353657772546716040589641726257477229849409426207693797722198701224860897069000
  print(a.modPow(b, BigInt.from(1000007))); // expect: 501168
  print(a.toRadixString(16)); // expect: 18ee90ff6c373e0ee4e3f0ad2
  print(a.compareTo(b)); // expect: 3
  print(a >> 10); // expect: 120563270519868827051986882
  print(a << 5); // expect: 3950617248395061724839506172480
  print(a.bitLength); // expect: 97
  print(a.gcd(b)); // expect: 9
  print((a & b) | (a ^ b)); // expect: 123456789012345678902052481779
  print(a.toDouble()); // expect: 1.2345678901234568e+29
  print(BigInt.two.toInt()); // expect: 2
  print(a == BigInt.parse('123456789012345678901234567890')); // expect: true
  print(a.hashCode == BigInt.parse('123456789012345678901234567890').hashCode);
  // expect: true
  print(BigInt.tryParse('x')); // expect: null
  print(BigInt.parse('-ff', radix: 16)); // expect: -255
  print(a.isEven); // expect: true
  print(a.sign); // expect: 1
  print(b.modInverse(BigInt.from(1000000007))); // expect: 152057246
}
