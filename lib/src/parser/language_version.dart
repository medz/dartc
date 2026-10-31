/// A Dart language major and minor version used for syntax checking.
///
/// The caller selects a file's version from its package and language-version
/// comment before parsing. Patch versions do not change the language version.
final class LanguageVersion implements Comparable<LanguageVersion> {
  /// Creates a language version from its [major] and [minor] components.
  const LanguageVersion(this.major, this.minor);

  /// The language version of the supported Dart SDK baseline.
  static const current = LanguageVersion(3, 13);

  /// The major version number.
  final int major;

  /// The minor version number.
  final int minor;

  @override
  int compareTo(LanguageVersion other) {
    final order = major.compareTo(other.major);
    return order == 0 ? minor.compareTo(other.minor) : order;
  }

  @override
  bool operator ==(Object other) =>
      other is LanguageVersion && major == other.major && minor == other.minor;

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => '$major.$minor';
}
