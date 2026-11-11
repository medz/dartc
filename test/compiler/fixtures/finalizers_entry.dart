import 'dart:async';

import 'finalizers.dart';

void main() {
  Timer.run(() {
    if (sequence != 12) throw StateError('timer order');
  });
  owner = Finalizer<double?>((value) {
    churn(20000);
    if (value != 3.25 || sequence != 12) throw StateError('finalizer order');
    scheduleMicrotask(() {
      if (sequence != 12) throw StateError('microtask order');
      Zone.current.print('finalized 中文🙂\ud800');
    });
  });
  attach();
  collect(0);
  if (sequence != 1) throw StateError('synchronous callback');
}

void attach() => owner!.attach(Cell(1), 3.25);
