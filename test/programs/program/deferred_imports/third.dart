final x = 'x';
var y = 'y'.length;
final lazy = () {
  print('initialized');
  return 3;
}();
int get got => 8;
set got(int v) => print('set $v');
int hidden = 0;
