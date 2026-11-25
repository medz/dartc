bool yes = true;
int a = trace(1);
void main() {
  if (!yes) a;
  print('then'); // expect: then
  truth(yes || a == 1); // expect: true
  truth(!yes || a == 1);
  // expect: 1
  // expect: true
}

void truth(bool b) => print(b);

int trace(int n) {
  print(n);
  return n;
}
