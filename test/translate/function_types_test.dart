import 'support.dart';

void main() {
  agrees('named parameters in runtime function types', r'''
    typedef AB = void Function({int? a, int? b});
    typedef BA = void Function({int? b, int? a});
    void ba({int? b, int? a}) {}
    void ab({int? a, int? b}) {}
    void requiredB({required int b, String? a}) {}
    class C { void ba({int? b, int? a}) {} }

    void main() {
      final first = ba.runtimeType, second = ab.runtimeType;
      print(first);
      print(second);
      print(first == second);
      print(C().ba.runtimeType == first);
      print({first: 1, second: 2}[C().ba.runtimeType]);
      print(BA);
      print(AB == BA);
      print(first == BA);
      print(second == BA);
      Object f = ba;
      print(f is AB);
      print(f is void Function({int? b}));
      print(f is void Function({int? c}));
      f = requiredB;
      print(f is void Function({String? a, required int b}));
      print(f is void Function({String? a, int b}));
      print(f is void Function({required num b}));
    }
  ''');

  agrees('named parameters when a generic function is instantiated', r'''
    typedef F = void Function<T>({T? a, T? z});
    void top<T>({T? z, T? a}) {}
    void nested<T>({void Function<U extends T>(U, T)? z, T? a}) {}
    void check(F f) {
      final type = f<int>.runtimeType;
      print(type);
      print(type == top<int>.runtimeType);
    }
    void main() {
      void local<T>({T? z, T? a}) {}
      print(top.runtimeType);
      print(local.runtimeType);
      check(top);
      check(local);
      final f = nested;
      print(f<num>.runtimeType);
      print(f<num>.runtimeType == nested<num>.runtimeType);
    }
  ''');
}
