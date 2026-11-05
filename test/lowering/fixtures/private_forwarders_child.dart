// ignore_for_file: use_primary_constructors
import 'private_forwarders.dart';
import 'private_forwarders_a.dart' as a;

class ForeignThrowChild extends Default {}

Object? privateThrowReuse(int form, dynamic value) =>
    a.invoke(ForeignThrowChild(), form, value);
