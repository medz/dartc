class BundledSource {
  final String uri;
  final String text;

  const BundledSource(this.uri, this.text);
}

class SourceBundle {
  final String runtime;
  final List<BundledSource> files;

  const SourceBundle(this.runtime, this.files);

  String? read(String uri) {
    for (final file in files) {
      if (file.uri == uri) return file.text;
    }
    return null;
  }
}
