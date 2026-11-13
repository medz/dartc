import 'dart:ffi' as ffi;

/// A machine instruction encoding.
enum Architecture() {
  arm64,
  x64,
}

/// An output platform's operating system.
enum OperatingSystem() {
  macos,
  linux,
}

/// An explicit output platform, independent of the compiler's host.
final class const Target(
  final OperatingSystem operatingSystem,
  final Architecture architecture,
) {
  /// Identifies the platform running this process.
  factory host() => switch (ffi.Abi.current()) {
    ffi.Abi.macosArm64 => const .new(.macos, .arm64),
    ffi.Abi.macosX64 => const .new(.macos, .x64),
    ffi.Abi.linuxArm64 => const .new(.linux, .arm64),
    ffi.Abi.linuxX64 => const .new(.linux, .x64),
    final abi => throw UnsupportedError('Unsupported host: $abi'),
  };

  /// The FFI ABI of the output, independent of the compiler's host.
  ffi.Abi get abi => switch ((operatingSystem, architecture)) {
    (.macos, .arm64) => ffi.Abi.macosArm64,
    (.macos, .x64) => ffi.Abi.macosX64,
    (.linux, .arm64) => ffi.Abi.linuxArm64,
    (.linux, .x64) => ffi.Abi.linuxX64,
  };

  /// Parses a platform name such as `linux-arm64`.
  factory parse(String value) {
    for (final os in OperatingSystem.values) {
      for (final arch in Architecture.values) {
        final target = Target(os, arch);
        if (target.toString() == value) return target;
      }
    }
    throw FormatException('Unknown target: $value');
  }

  @override
  bool operator ==(Object other) =>
      other is Target &&
      operatingSystem == other.operatingSystem &&
      architecture == other.architecture;

  @override
  int get hashCode => Object.hash(operatingSystem, architecture);

  @override
  String toString() => '${operatingSystem.name}-${architecture.name}';
}
