// What profiles of HTTP and WebSockets need, which programs without isolates
// and a service do not have.

@patch
class _WebSocketProfileData {
  // There is one isolate, which the service does not name.
  @patch
  static final String isolateId = '';
}
