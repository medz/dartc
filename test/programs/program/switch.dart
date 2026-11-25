// over double
int? overDouble() {
  var d = 1.0, n = 0;
  switch (d) {
    case 1:
      n += 1;
    default:
      n += 2;
  }
  d = 0;
  switch (d) {
    case -0.0:
      n += 10;
    default:
      n += 20;
  }
  return n;
}

// without a default
int? withoutADefault() {
  var n = 1;
  switch (n) {
    case 2:
      n = 5;
  }
  return n;
}

// over bool
int? overBool() {
  switch (1 < 2) {
    case true:
      return 3;
    case false:
      return 4;
  }
}

// sharing the default
int? sharingTheDefault() {
  switch (9) {
    case 1:
    default:
      return 8;
  }
}

// with an empty last case
int? withAnEmptyLastCase() {
  switch (9) {
    case 1:
      return 1;
    case 9:
  }
  return 2;
}

// continue inside goes to the loop
int? continueInsideGoesToTheLoop() {
  var n = 0;
  for (var i = 0; i < 5; i++) {
    switch (i) {
      case 2:
        continue;
      case 3:
        break;
    }
    n += i;
  }
  return n;
}

// its value is read once
int? itsValueIsReadOnce() {
  var n = 1;
  switch (n++) {
    case 1:
      n += 10;
    case 2:
      n += 100;
  }
  return n;
}

void main() {
  print(overDouble()); // expect: 11
  print(withoutADefault()); // expect: 1
  print(overBool()); // expect: 3
  print(sharingTheDefault()); // expect: 8
  print(withAnEmptyLastCase()); // expect: 2
  print(continueInsideGoesToTheLoop()); // expect: 8
  print(itsValueIsReadOnce()); // expect: 12
}
