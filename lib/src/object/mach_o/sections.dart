import '../section.dart';

/// Mach-O names and flags for the supported storage kinds.
extension MachOSectionKind on SectionKind {
  /// The section name used in Mach-O records.
  String get machName => switch (this) {
    .code => '__text',
    .readOnlyData => '__const',
    .data => '__data',
    .zeroFill => '__bss',
  };

  /// The containing segment name.
  String get machSegment => switch (this) {
    .code => '__TEXT',
    .readOnlyData => '__CONST',
    .data || .zeroFill => '__DATA',
  };

  /// The section type and instruction attributes.
  int get machFlags => switch (this) {
    .code => 0x80000400,
    .zeroFill => 1,
    _ => 0,
  };
}
