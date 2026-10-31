import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

const programs = <String, (String, Set<Type>)>{
  'library directives and annotated declarations': (
    '''
@deprecated library sample;
import 'base.dart' if (dart.library.io) 'native.dart' deferred as platform
  show Service, Result hide Internal;
export 'public.dart' show Service;
part 'implementation.dart';
@Mark<int>.named(1)
final result = platform.Service<int>.new;
''',
    {
      LibraryDirective,
      ImportDirective,
      ConditionalUri,
      NamespaceCombinator,
      ExportDirective,
      PartDirective,
      Annotation,
      TopLevelVariableDeclaration,
      PropertyAccessExpression,
    },
  ),
  'classes, constructors, aliases and extensions': (
    '''
abstract interface class Contract<T> { T get value; }
base mixin Cache<T> on Base<T> implements Contract<T> {
  late T cached;
  T get value => cached;
  set value(covariant T next) { cached = next; }
}
class const Box<T>.named(final T value) extends Base<T> with Cache<T>
    implements Contract<T> {
  this : assert(value != null), super(value);
  const new(T value) : this.named(value);
  factory from(T value) => Box<T>.named(value);
  factory redirect(T value) = Other<T>.named;
  T operator [](int index) => value;
  void operator []=(int index, T next) {}
  external T native(T value);
}
class Alias<T> = Base<T> with Cache<T>;
class Pair {
  final int value;
  Pair(int next) : value = next;
}
enum Choice<T> implements Contract<T> {
  first<int>(1), second<String>.named('two');
  const Choice(this.value);
  const Choice.named(this.value);
  final T value;
}
extension Values<T> on List<T> { T firstValue() => this[0]; }
extension<T> on Iterable<T> { List<T> copy() => [...this]; }
extension type const Id<T>.new(T value) implements Object;
sealed class State;
final class Done extends State;
''',
    {
      ClassDeclaration,
      MixinDeclaration,
      ClassTypeAliasDeclaration,
      EnumDeclaration,
      EnumConstantDeclaration,
      ExtensionDeclaration,
      ExtensionTypeDeclaration,
      PrimaryConstructorBody,
      ConstructorDeclaration,
      FactoryRedirectBody,
      FieldInitializer,
      AssertInitializer,
      SuperConstructorInitializer,
      RedirectingConstructorInitializer,
      GetterDeclaration,
      SetterDeclaration,
      OperatorDeclaration,
      MethodDeclaration,
    },
  ),
  'types, formal parameters and nested functions': (
    r'''
typedef Mapper<T extends Object> = ({T value, int count}) Function(
  T, {required T Function(T) convert});
typedef R Legacy<R, T>(T value, [R fallback]);
void visit<T extends Object>(
  @deprecated (T, {String label}) value,
  void callback<U>(U value), {
  required T Function(T) convert,
  int count = 1,
}) {
  @deprecated
  R local<R extends Object>(R value) => value;
  final closure = <U extends Object>(U item) => (item, label: 'value');
  final instantiated = local<T>;
  callback(closure(value.$1));
}
''',
    {
      TypeAliasDeclaration,
      FunctionTypeAliasDeclaration,
      RecordTypeAnnotation,
      FunctionTypeAnnotation,
      FunctionParameterSuffix,
      FormalParameter,
      ParameterDefault,
      LocalFunctionDeclaration,
      FunctionExpression,
      TypeInstantiationExpression,
      RecordExpression,
    },
  ),
  'statements, exceptions and asynchronous contexts': (
    '''
Stream<int> values(Stream<(int, int)> input) async* {
  outer: for (var i = 0, j = 1; i < 10; i++, j += 2) {
    while (ready) { if (i == j) continue outer; break; }
    do { i--; } while (i > 0);
  }
  await for (final (left, right) in input) {
    try {
      assert(left >= 0, 'negative');
      if (await allowed(left)) yield left + right;
      else yield* other();
    } on StateError catch (error, stack) {
      rethrow;
    } catch (error) {
      throw error;
    } finally {
      await close();
    }
  }
  final generated = () sync* { yield 1; yield* [2]; return; };
  final delayed = () async => await load();
  final synchronous = () { var await = 1; return await; };
  ;
  return;
}
''',
    {
      ForStatement,
      ForParts,
      ForInParts,
      LabeledStatement,
      WhileStatement,
      DoStatement,
      ContinueStatement,
      BreakStatement,
      TryStatement,
      CatchClause,
      AssertStatement,
      RethrowStatement,
      ThrowExpression,
      YieldStatement,
      AwaitExpression,
      EmptyStatement,
      ModifiedBlockFunctionBody,
    },
  ),
  'patterns, guards, switches and destructuring': (
    '''
Object classify(Object? input) {
  final (first, label: label) = record;
  var [head, ...tail] = items;
  (first, label: label) = record;
  [head, ...tail] = items;
  if (input case Box<int>(value: var value) when value > 0) return value;
  switch (input) {
    again: case [int first, ...var rest] when first > 0:
      return rest;
    case {'name': String name}:
      return name;
    case (var left, right: var right):
      return left;
    case null:
      continue again;
    default:
      break;
  }
  return switch (input) {
    >= 1 && <= 10 || -1 => 'small',
    (var x as int)? => x,
    var x! => x,
    const (1 + 2) => 'three',
    _ => 'other',
  };
}
''',
    {
      PatternVariableDeclaration,
      PatternAssignmentExpression,
      IfStatement,
      SwitchStatement,
      SwitchExpression,
      GuardedPattern,
      ObjectPattern,
      ListPattern,
      MapPattern,
      RecordPattern,
      RestPatternElement,
      LogicalPattern,
      RelationalPattern,
      CastPattern,
      NullCheckPattern,
      NullAssertPattern,
      ConstantPattern,
      WildcardPattern,
    },
  ),
  'collections, selectors, literals and operators': (
    r'''
Future<Object> build(Stream<(int, int)> input) async {
  final values = <Object?>[
    ?optional, ...items, ...?nullable,
    if (input case var current when ready) current else null,
    for (var (left, right) in pairs) left + right,
    await for (final (left, right) in input) left * right,
  ];
  final map = <String, int>{?key: ?number, 'one': 1, ...entries};
  final symbols = {#name, #library.name, #void, #[]=};
  final record = const (1, flag: true);
  final string = r'raw\text' ' value: ${values[0]} $this';
  final created = new p.Box<int>.named(1);
  final constant = const p.Box<int>(1);
  final shorthand = const .named<int>(1);
  final configured = make()?..value = .defaultValue..run<int>();
  final access = receiver?.child?[index]!.call<int>(named: 1, 2);
  receiver[index] ??= ready ? (value as int?) : null;
  receiver.value += ((a << 2) | b) & (~c ^ d) >>> 1;
  receiver[index]++;
  --receiver.value;
  return !(value is! int) && ready || false ? values : throw failure;
}
''',
    {
      CollectionExpression,
      NullAwareElement,
      SpreadElement,
      MapEntryElement,
      IfElement,
      ForElement,
      LiteralExpression,
      RecordExpression,
      AdjacentStringsExpression,
      StringInterpolation,
      InstanceCreationExpression,
      ConstDotShorthandExpression,
      CascadeExpression,
      IndexExpression,
      NullAssertionExpression,
      InvocationExpression,
      AssignmentExpression,
      UpdateExpression,
      ConditionalExpression,
      TypeTestExpression,
      CastExpression,
    },
  ),
};

void main() {
  test(
    'unfinished switch labels retain their missing case and enclosing end',
    () {
      for (final text in [
        'void f() { switch (value) { next:',
        'void f() { switch (value) { first: next: } } int following = 1;',
      ]) {
        final result = parseCompilationUnit(
          scan(SourceFile(Uri.parse('memory:label'), text)),
        );
        expect(result.hasErrors, isTrue);
        final statement = walk(result.node).whereType<SwitchStatement>().single;
        final member = statement.members.single;
        expect(member.labels.last.name.text, 'next');
        expect(member.pattern, isA<MissingPattern>());
        expect(member.statements, isEmpty);
        if (text.endsWith(';')) {
          final field = result.node.members.last as TopLevelVariableDeclaration;
          expect(field.variables.declarations.single.name.text, 'following');
        }
      }
    },
  );

  for (final MapEntry(key: name, value: (text, expectedTypes))
      in programs.entries) {
    test('compilation unit combines $name', () {
      final input = scan(SourceFile(Uri.parse('memory:language'), text));
      final tokens = [...input.tokens];
      final result = parseCompilationUnit(input);
      expect(
        result.diagnostics.map((d) => '${d.code}: ${d.span?.text}'),
        isEmpty,
      );
      expect(result.node.text, text);
      expect(input.tokens, orderedEquals(tokens));
      final nodes = walk(result.node).toList();
      expect(
        nodes.map((n) => n.runtimeType).toSet(),
        containsAll(expectedTypes),
      );
      for (final node in nodes) {
        expect(node.source, same(input.source));
        expect(node.length, greaterThan(0), reason: '${node.runtimeType}');
        var end = node.start;
        for (var i = 0; i < node.childCount; i++) {
          final child = node.childAt(i);
          expect(child.start, greaterThanOrEqualTo(end));
          expect(child.end, lessThanOrEqualTo(node.end));
          end = child.end;
        }
      }
    });

    test('truncated $name returns a source-preserving unit', () {
      final source = SourceFile(Uri.parse('memory:incomplete'), text);
      for (final token in scan(source).tokens) {
        final prefix = SourceFile(source.uri, text.substring(0, token.start));
        final input = scan(prefix);
        final tokens = [...input.tokens];
        final result = parseCompilationUnit(input);
        expect(result.node.source, same(prefix));
        expect(result.node.text, prefix.text);
        expect(input.tokens, orderedEquals(tokens));
        for (final diagnostic in result.diagnostics) {
          expect(diagnostic.span?.source, same(prefix));
        }
      }
    });
  }
}
