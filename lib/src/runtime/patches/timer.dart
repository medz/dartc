import '../allocator.dart' as allocator;

@patch
class Timer {
  static Timer _createTimer(Duration duration, void Function() callback) =>
      allocator.events().createTimer(duration, (_) => callback(), false);

  static Timer _createPeriodicTimer(
    Duration duration,
    void callback(Timer timer),
  ) => allocator.events().createTimer(duration, callback, true);
}
