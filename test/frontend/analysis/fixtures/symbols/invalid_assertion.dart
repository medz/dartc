class Checked {
  const Checked() : assert(#_secret == const Symbol('_secret'));
}

const value = Checked();
