import 'dart:async';

/// Reads decoded source text for a URI, synchronously or asynchronously.
///
/// Returns `null` when no source exists at the URI. Other read failures throw
/// or complete with an error. The caller resolves the URI and owns the source
/// snapshot; the provider preserves the text without normalization.
typedef SourceProvider = FutureOr<String?> Function(Uri uri);
