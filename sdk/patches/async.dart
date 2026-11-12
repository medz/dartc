import '../runtime/allocator.dart' as allocator;

@patch
class _AsyncRun {
  @patch
  static void _scheduleImmediate(void Function() callback) =>
      allocator.events().scheduleMicrotasks(callback);
}
