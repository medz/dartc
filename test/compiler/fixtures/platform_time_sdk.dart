import 'platform_time_cases.dart';

void main() {
  for (final seconds in timeZoneInstants) {
    final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    print('${date.timeZoneName}:${date.timeZoneOffset.inSeconds}');
  }
}
