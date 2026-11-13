class NativeOnly {
  const NativeOnly()
    : assert(!const bool.fromEnvironment('dart.library.js_interop'));
}

const unused = NativeOnly();
