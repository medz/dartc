// ignore_for_file: annotate_overrides, use_primary_constructors, curly_braces_in_flow_control_structures
import 'typed_forwarders_private.dart';
import 'effects.dart' as effects;

class ForeignForwardChild extends PrivateForwardBase {}

class ForeignForwardMiddleChild extends PrivateForwardMiddle {}

class ForeignForwardOverride extends PrivateForwardBase {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(92);
    return 99;
  }
}

Object? forwardPrivateInheritance(int form, bool tearoff) {
  if (form == 0) return invokePrivateForward(ForeignForwardChild(), tearoff);
  if (form == 1)
    return invokePrivateForward(ForeignForwardMiddleChild(), tearoff);
  return invokePrivateForward(ForeignForwardOverride(), tearoff);
}
