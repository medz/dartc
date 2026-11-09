const integer = 9007199254740993;
const floating = 9007199254740992.0;

class const Above(num value) {
  this : assert(value > floating, 'Expected a greater value.');
}

class const Equal(num value) {
  this : assert(value == floating, 'Expected equal values.');
}
