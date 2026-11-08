import 'package:dartc/target.dart';

/// Native symbol spelling for the selected platform ABI.
extension NativeSymbols on Target {
  /// Decorates an explicit C function name for this target's object format.
  String nativeSymbol(String name) =>
      operatingSystem == .macos ? '_$name' : name;
}
