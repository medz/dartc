void main() {
  for (var f = 0; f < 16; f++)
    print(
      RegExp(
        'a',
        caseSensitive: f & 1 == 0,
        multiLine: f & 2 != 0,
        dotAll: f & 4 != 0,
        unicode: f & 8 != 0,
      ),
    );
  // expect: RegExp: pattern=a flags=
  // expect: RegExp: pattern=a flags=i
  // expect: RegExp: pattern=a flags=m
  // expect: RegExp: pattern=a flags=im
  // expect: RegExp: pattern=a flags=s
  // expect: RegExp: pattern=a flags=is
  // expect: RegExp: pattern=a flags=ms
  // expect: RegExp: pattern=a flags=ims
  // expect: RegExp: pattern=a flags=u
  // expect: RegExp: pattern=a flags=iu
  // expect: RegExp: pattern=a flags=mu
  // expect: RegExp: pattern=a flags=imu
  // expect: RegExp: pattern=a flags=su
  // expect: RegExp: pattern=a flags=ius
  // expect: RegExp: pattern=a flags=msu
  // expect: RegExp: pattern=a flags=imsu
}
