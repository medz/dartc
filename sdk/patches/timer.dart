import '../runtime/allocator.dart' as allocator;

@patch
class Timer {
  @patch
  static Timer _createTimer(Duration duration, void Function() callback) =>
      allocator.events().createTimer(duration, (_) => callback(), false);

  @patch
  static Timer _createPeriodicTimer(
    Duration duration,
    void callback(Timer timer),
  ) => allocator.events().createTimer(duration, callback, true);
}
