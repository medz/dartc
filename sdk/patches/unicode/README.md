# Unicode case data

These unmodified inputs are from Unicode 17.0.0 in
[unicode-org/unicodetools](https://github.com/unicode-org/unicodetools/tree/ccc86e576dcadf94ef9f86969e7b5cb51e432ddc/unicodetools/data/ucd/17.0.0),
commit ccc86e576dcadf94ef9f86969e7b5cb51e432ddc. The adjacent LICENSE is from
that same commit.

UnicodeData.txt supplies simple mappings, SpecialCasing.txt supplies full
mappings, and DerivedCoreProperties.txt supplies Cased and Case_Ignorable.
The language-independent Final_Sigma condition is evaluated against the
original string by the ordinary Dart case-conversion leaf. Locale-specific
tailoring is outside String.toLowerCase/toUpperCase.

The SDK source provider checks the input SHA-256 pins and materializes Dart
constants at sdk/patches/unicode_case_data.dart in its source view. Source
directories and archives expose that module and the license, while the three
original data files remain repository inputs for generation and validation.
Packaging rejects missing or modified inputs. The archive runs independently
of those inputs, with no network lookup or target-side text parsing. Generated
files are build artifacts; update these original inputs and their pins together.

The pinned Dart VM uses an older simple mapping. Full mapping follows the
[accepted Dart contract correction](https://github.com/dart-lang/sdk/issues/6706#issuecomment-108340484),
including sharp-s expansion, dotted-I expansion and contextual final sigma.
