import 'dart:_heap/objects.dart' show currentUri;

@patch
class Uri {
  @patch
  static Uri get base => currentUri() as Uri;
}
