import 'dart:async';

int zoneCall(int value) => runZoned(() => value + 1);

int zoneValue(int value) => runZoned(
  () => value + (Zone.current[#offset] as int),
  zoneValues: {#offset: 3},
);

int restoredZone(int value) {
  final before = Zone.current;
  final result = runZoned(() {
    try {
      return runZoned<int>(() => throw value);
    } on int catch (error) {
      return error + 2;
    }
  });
  return identical(Zone.current, before) ? result : -1;
}

int redirectedPrint(int value) {
  var observed = 0;
  runZoned(
    () => print('message'),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        observed = value + line.length;
      },
    ),
  );
  return observed;
}
