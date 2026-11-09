/// The native file requested from a compilation.
sealed class const Output() {
  /// A standalone executable using the first input library's `main`.
  const factory executable() = ExecutableOutput;

  /// A relocatable object file.
  const factory object() = ObjectOutput;

  /// An indexed static library.
  const factory staticLibrary() = StaticLibraryOutput;

  /// A shared library whose identity is [name], independent of its write path.
  ///
  /// Compilation rejects empty names and embedded NUL characters.
  const factory sharedLibrary(String name) = SharedLibraryOutput;
}

/// A standalone executable request.
final class const ExecutableOutput() extends Output;

/// A relocatable object file request.
final class const ObjectOutput() extends Output;

/// A static library request.
final class const StaticLibraryOutput() extends Output;

/// A shared library request with an explicit library identity.
final class const SharedLibraryOutput(final String name) extends Output;
