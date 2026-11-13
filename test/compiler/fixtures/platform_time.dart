import '../../../sdk/patches/date_time.dart';

import 'platform_time_cases.dart';

void main() {
  print(currentTimeMicros());
  for (final seconds in timeZoneInstants) {
    print('${timeZoneName(seconds)}:${timeZoneOffsetInSeconds(seconds)}');
  }
}
