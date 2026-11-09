// ignore_for_file: non_exhaustive_switch_expression

int nested(bool outer, bool inner) => switch (outer) {
  true => switch (inner) {
    true => 1,
  },
  false => 2,
};
