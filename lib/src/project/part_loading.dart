part of 'load.dart';

typedef _PartInput = (SourceFile, Uri, LanguageVersion);

List<LibraryUnit> _parseParts(List<_PartInput> batch) => [
  for (final (source, location, version) in batch)
    _parseUnit(source, location, version),
];

Future<List<LibraryUnit>> _parseInWorker(List<_PartInput> batch) =>
    Isolate.run(() => _parseParts(batch));

extension on _Load {
  // Part bodies cannot introduce dependencies. Read them during discovery and
  // leave inclusion, diagnostics and publication to the ordered traversal.
  Future<void> prepareParts(LibraryUnit initial) async {
    final ready = staged ??= {};
    final seen = {...libraries.keys, initial.source.uri};
    final definitions = <Uri>[];
    final parts = <Uri>{};
    final waiting = Queue<(Uri, Uri)>();
    final readers = <Future<void>>[];
    var active = 0;

    final tasks = <Future<void>>[];
    final parallel = Platform.numberOfProcessors > 1;
    var workerBusy = false;
    var size = 0;
    var batch = <_PartInput>[];
    void store(List<LibraryUnit> units) {
      for (final unit in units) {
        ready[unit.source.uri] = unit;
      }
    }

    Future<void> readParts() async {
      active++;
      try {
        while (waiting.isNotEmpty && !providerError) {
          final (uri, location) = waiting.removeFirst();
          final (text, _) = texts[location] ?? await readText(location);
          if (text == null || providerError) continue;
          batch.add((SourceFile(uri, text), location, loader._versionFor(uri)));
          size += text.length;
          if (size >= 192 * 1024) {
            final work = batch;
            batch = [];
            size = 0;
            if (!parallel || workerBusy) {
              store(_parseParts(work));
            } else {
              workerBusy = true;
              final task = _parseInWorker(work)
                  .then(store)
                  .whenComplete(() => workerBusy = false);
              task.ignore();
              tasks.add(task);
            }
          }
        }
      } finally {
        active--;
      }
    }

    void library(Uri uri) {
      if (!seen.add(uri) || parts.contains(uri)) return;
      definitions.add(uri);
      if (pending.length < _Load._readAhead) prefetch(uri);
    }

    void discover(LibraryUnit unit) {
      if (unit.diagnostics.isNotEmpty) return;
      for (final directive in _directives(unit)) {
        try {
          switch (directive) {
            case ImportDirective(:final uri, configurations: []) ||
                ExportDirective(:final uri, configurations: []):
              library(_resolve(uri, unit.source.uri));
            case PartDirective():
              final uri = _resolve(directive.uri, unit.source.uri);
              if (seen.contains(uri) || !parts.add(uri)) continue;
              final location = loader._sourceLocation(uri);
              if (location == null) continue;
              waiting.add((uri, location));
              if (active < 16) {
                final reading = readParts();
                readers.add(reading);
                reading.ignore();
              }
            default:
              break;
          }
        } on FormatException {
          // The consuming directive reports its URI error in source order.
        }
      }
      library(_coreLibrary);
    }

    for (final (uri, _) in queue) {
      library(uri);
    }
    discover(initial);
    for (var i = 0; i < definitions.length && !providerError; i++) {
      final uri = definitions[i], location = loader._sourceLocation(uri);
      if (location == null) continue;
      final (text, _) = texts[location] ?? await readText(location);
      if (text != null && !providerError) {
        discover(ready[uri] ??= loader._parse(uri, location, text, null));
      }
    }
    await Future.wait(readers);
    if (!providerError) store(_parseParts(batch));
    await Future.wait(tasks);
  }
}
