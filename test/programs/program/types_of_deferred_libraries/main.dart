import 'other.dart' deferred as o;

void main() => print(o.G<int>); // error 22: A type of a deferred library has no type arguments here.
