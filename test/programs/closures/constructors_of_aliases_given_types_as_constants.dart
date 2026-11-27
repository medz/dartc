class C<T> {}

typedef Alias<X, Y> = C<X>;

const make = Alias.new;
const specialized = make<int, String>;

void main() => print(specialized == C<int>.new); // error 22: Not supported yet: a constant of type C<int> Function().
