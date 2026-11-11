import '../allocator.dart' as allocator;

@patch
class _AsyncRun {
  static void _scheduleImmediate(void Function() callback) =>
      allocator.events().scheduleMicrotasks(callback);
}
