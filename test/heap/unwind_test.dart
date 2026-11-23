import 'package:dartc/heap.dart';
import 'package:test/test.dart';

import 'simulated.dart';

void main() {
  late SimulatedMachine simulated;
  setUp(() => machine = simulated = SimulatedMachine());

  group('throwing', () {
    /// Return addresses of frames, by the number of references in them.
    int returns(int references) =>
        100 + SimulatedMachine.frameSizes.indexOf(references) * 4;

    void run() => expect(() => raise('e', 't'), throwsA(isA<Resumed>()));

    test('continues in the innermost caller with a handler', () {
      simulated
        ..frames.addAll([
          [0, 0],
          [0],
          [0, 0],
          [],
        ])
        ..targets.addAll({returns(1): 700, returns(2): 800});
      run();
      final resumed = simulated.resumed!;
      expect(resumed.code, simulated.codeStart + 800);
      expect((resumed.exception, resumed.trace), ('e', 't'));
      // The frame that called the third function, which is the second's.
      final innermost = simulated.frameAddress;
      final third = simulated.load64(innermost);
      expect(resumed.frame, simulated.load64(third));
    });

    test('finds any of many handlers', () {
      for (var i = 0; i < 40; i++) {
        simulated.targets[1000 + i * 12] = i + 1;
      }
      for (final size in SimulatedMachine.frameSizes) {
        simulated
          ..frames.clear()
          ..frames.add(List.filled(size, 0))
          ..targets[returns(size)] = 5000 + size;
        run();
        expect(simulated.resumed!.code, simulated.codeStart + 5000 + size);
      }
    });

    test('stops where no caller has a handler', () {
      simulated.frames.addAll([
        [],
        [0],
      ]);
      expect(() => raise('e', 't'), throwsStateError);
      expect(simulated.resumed, isNull);
    });
  });
}
