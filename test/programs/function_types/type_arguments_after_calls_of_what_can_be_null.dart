class C {
  C Function() f() =>
      () => this;
  T m<T>(T x) => x;
}

void show(C? c) => print(c?.f()().m<int>); // error 26: What gets type arguments here can be null.

void main() => show(C());
