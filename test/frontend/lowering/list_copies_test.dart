import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../compiler/fixtures/lists.dart' as sdk;
import 'fixture_comparison.dart';

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await AnalysisSession(['test/compiler/fixtures/lists.dart']).use(
      (input) async =>
          FixtureComparison((await Lowering().lower(input)).program),
    );
  });

  test('List factories and inherited ranges match their source behavior', () {
    for (final kind in [0, 1, 2, 3, 4, 5]) {
      for (final growable in [0, 1]) {
        fixture.compare('listCopy', [
          kind,
          growable,
        ], () => sdk.listCopy(kind, growable));
      }
      for (final (start, end) in [
        (1, -1),
        (1, -2),
        (0, 0),
        (-1, 2),
        (2, 1),
        (0, 5),
      ]) {
        fixture.compare('listSlice', [
          kind,
          start,
          end,
        ], () => sdk.listSlice(kind, start, end));
      }
    }
    for (final kind in [0, 1]) {
      for (final failure in [0, 1, 2]) {
        fixture.compare('listCopyProtocol', [
          kind,
          failure,
        ], () => sdk.listCopyProtocol(kind, failure));
      }
    }
    for (final kind in [0, 1, 2, 3]) {
      fixture.compare('listSliceMutability', [
        kind,
      ], () => sdk.listSliceMutability(kind));
      fixture.compare('listSlicePattern', [
        kind,
      ], () => sdk.listSlicePattern(kind));
    }
    fixture.compare('listSliceReferences', [
      0,
    ], () => sdk.listSliceReferences(0));
  });
}
