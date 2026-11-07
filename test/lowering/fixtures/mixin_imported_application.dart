import 'mixin_imported_base.dart';

mixin Accept {
  int accept(int value) => value;
}

class Applied() extends Base with Accept;

int run() => Applied().accept(1);
