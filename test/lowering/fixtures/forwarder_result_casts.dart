// ignore_for_file: annotate_overrides, use_primary_constructors, unnecessary_type_name_in_constructor
abstract class ResultContract<T> {
  dynamic any();
  Object? nullableObject();
  int narrow();
  T generic();
  Never impossible();
  void ignored();
}

class ResultBox<T> implements ResultContract<T> {
  final dynamic answer;
  ResultBox(this.answer);
  dynamic noSuchMethod(Invocation invocation) => answer;
}

Object? forwardResult(int form, dynamic answer) {
  dynamic box = ResultBox<int>(answer);
  if (form == 0) return box.any();
  if (form == 1) return box.nullableObject();
  if (form == 2) return box.narrow();
  if (form == 3) return box.generic();
  if (form == 4) return box.impossible();
  return box.ignored();
}
