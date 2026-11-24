enum OperatingSystem() {
  macos,
  linux,
}

enum Architecture() {
  arm64,
  x64,
}

/// What programs are compiled for.
enum Target(final OperatingSystem system, final Architecture architecture) {
  macosArm64(.macos, .arm64),
  linuxArm64(.linux, .arm64),
  linuxX64(.linux, .x64);

  /// What it is called in commands, and by the SDK.
  String get label => '${system.name}_${architecture.name}';
}
