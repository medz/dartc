// ignore_for_file: curly_braces_in_flow_control_structures, annotate_overrides, unused_element, unused_element_parameter, unnecessary_type_check, use_primary_constructors
abstract class Contract {
  String _f({String value = 'b'});
}

Object? invoke(dynamic receiver, int form) {
  if (form == 0) return receiver._f();
  if (form == 1) return receiver._f is String Function({String value});
  if (form == 2) return receiver._f(1);
  final dynamic tear = receiver._f;
  return tear();
}

class SymbolCapture {
  dynamic noSuchMethod(Invocation invocation) => invocation.memberName;
}

bool origin(Symbol name) {
  final dynamic capture = SymbolCapture();
  return name == capture._f();
}
