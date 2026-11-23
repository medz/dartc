import 'package:dartc/src/source/patch.dart';
import 'package:test/test.dart';

/// The texts of a library after patching it.
Map<String, String> patch(
  Map<String, String> files,
  List<String> patches, {
  String main = 'lib.dart',
}) => patchLibrary(files, main, {
  for (final (i, text) in patches.indexed) 'patch$i.dart': text,
}, added: 'added');

void main() {
  test('members replace those they patch', () {
    final files = patch(
      {
        'lib.dart': '''
library x;
part 'part.dart';
class A {
  /// Says what it is.
  external int get f;
  external set f(int value);
  external A.named(int x);
  external A operator -();
  external A operator -(A other);
  int kept() => 1;
}
''',
        'part.dart': '''
part of 'lib.dart';
mixin M { external void m(); }
external int g();
external int get h;
''',
      },
      [
        '''
@patch
class A {
  @patch
  int get f => 1;
  @patch
  set f(int value) {}
  @patch
  @pragma('p')
  A.named(int x);
  @patch A operator -() => this;
  @patch A operator -(A other) => other;
}
@patch mixin M { @patch void m() { } }
@patch int g() => 2;
@patch int get h => 3;
''',
      ],
    );
    expect(files['lib.dart'], '''
library x;
part 'part.dart';
class A {
  /// Says what it is.
  int get f => 1;
  set f(int value) {}
  @pragma('p') A.named(int x);
  A operator -() => this;
  A operator -(A other) => other;
  int kept() => 1;
}
''');
    expect(files['part.dart'], '''
part of 'lib.dart';
mixin M { void m() { } }
int g() => 2;
int get h => 3;
''');
    expect(files.keys, ['lib.dart', 'part.dart']);
  });

  test('a field replaces a getter and a setter', () {
    final files = patch(
      {'lib.dart': 'class A { external int get f; external set f(int v); }'},
      ['@patch class A { @patch int f = 1; }'],
    );
    expect(files['lib.dart'], 'class A { int f = 1;  }');
  });

  test('other declarations are added', () {
    final files = patch(
      {
        'lib.dart': '''
library x;
import 'dart:a';
part 'part.dart';
class A {}
class B {}
''',
        'part.dart': "part of 'lib.dart';\nint x = 1;\n",
      },
      [
        '''
import 'dart:b' show c;
part 'other.dart';
@patch
@pragma('q', 'r')
class A { int added = 1; }
class C {}
''',
        "part of 'patch0.dart';\nint y = 2;\n",
      ],
    );
    expect(files['lib.dart'], '''
library x;
import 'dart:a';
import 'dart:b' show c;
part 'part.dart';
part 'added0.dart';
@pragma('q', 'r') class A {
int added = 1;
}
class B {}
''');
    expect(files['added0.dart'], '''
part of 'lib.dart';

class C {}

int y = 2;
''');
  });

  test('patches can be patched', () {
    final first = patch(
      {'lib.dart': 'external int f();'},
      ['@patch int f() => A().x(); class A { external int x(); }'],
    );
    final second = patchLibrary(first, 'lib.dart', {
      'p.dart': '@patch class A { @patch int x() => 4; }',
    }, added: 'more');
    expect(second['added0.dart'], contains('class A { int x() => 4; }'));
    expect(second['lib.dart'], contains('int f() => A().x();'));
    expect(second.containsKey('more0.dart'), isFalse);
  });

  test('what a patch patches must exist', () {
    for (final (text, message) in [
      ('@patch class B {}', 'B'),
      ('@patch int f() => 1;', 'f'),
      ('@patch class A { @patch int f() => 1; }', 'A.f'),
    ]) {
      expect(
        () => patch({'lib.dart': 'class A {}'}, [text]),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'patch0.dart patches $message, which there is not.',
          ),
        ),
      );
    }
  });
}
