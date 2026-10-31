import 'dart:math';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

ParseResult<CompilationUnit> parse(String text) => parseCompilationUnit(
  scan(SourceFile(Uri.parse('memory:declarations'), text)),
);

TopLevelDeclaration declaration(String text) {
  final result = parse(text);
  expect(
    result.diagnostics.map((d) => '${d.code}: ${d.span?.text}'),
    isEmpty,
    reason: text,
  );
  return result.node.members.single as TopLevelDeclaration;
}

void main() {
  test('unfinished assertion initializers return diagnostics and syntax', () {
    for (final text in [
      'class C { C() : assert',
      'class C { C() : assert(',
      'class C() { this : assert',
      'class C { C() : assert; int following = 1; }',
    ]) {
      final result = parse(text);
      expect(result.hasErrors, isTrue, reason: text);
      final assertion = walk(result.node).whereType<AssertInitializer>().single;
      expect(assertion.condition, isA<MissingExpression>());
      expect(assertion.end, lessThanOrEqualTo(text.length));
      if (text.endsWith('}')) {
        final field = walk(result.node).whereType<FieldDeclaration>().single;
        expect(field.variables.declarations.single.name.text, 'following');
      }
    }
  });

  test('generic factory methods remain methods in every member container', () {
    for (final text in [
      'class C { factory<T>(T value) => value; }',
      'mixin M { factory<T>(T value) => value; }',
      'enum E { one; factory<T>(T value) => value; }',
      'extension X on int { factory<T>(T value) => value; }',
      'extension type E(int value) { factory<T>(T value) => value; }',
    ]) {
      final result = declaration(text);
      final method = walk(result).whereType<MethodDeclaration>().single;
      expect(method.name.text, 'factory');
      expect(method.typeParameters!.text, '<T>');
      expect(method.parameters.text, '(T value)');
      expect(walk(result).whereType<ConstructorDeclaration>(), isEmpty);
    }
  });

  test('covariant setters retain their modifier', () {
    final cls = declaration(
      'abstract class C { covariant set x(int value); }',
    ) as ClassDeclaration;
    expect((cls.members.single as SetterDeclaration).isCovariant, isTrue);
    for (final text in [
      'abstract sealed class C {}',
      'interface mixin class C {}',
      'sealed mixin M {}',
      'mixin M with N {}',
      'extension X on int implements I {}',
      'class C { static void f(); }',
      'class C { static C(); }',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
  });

  test(
    'class headers retain modifiers, type parameters and ordered clauses',
    () {
      final cls = declaration(
        '@A() abstract base class C<T extends Object> extends B<T> with M,N implements I,J {}',
      ) as ClassDeclaration;
      expect(cls.metadata.single.text, '@A()');
      expect(cls.modifiers, [
        ClassModifier.abstractKeyword,
        ClassModifier.baseKeyword,
      ]);
      expect(cls.typeParameters!.text, '<T extends Object>');
      expect(cls.extendsClause!.superclass.text, 'B<T>');
      expect(cls.withClause!.types.map((t) => t.text), ['M', 'N']);
      expect(cls.implementsClause!.types.map((t) => t.text), ['I', 'J']);
      final alias = declaration(
        'class C<T> = B<T> with M<T> implements I;',
      ) as ClassTypeAliasDeclaration;
      expect(alias.superclass.text, 'B<T>');
      expect(alias.withClause.types.single.text, 'M<T>');
      expect(alias.implementsClause!.types.single.text, 'I');
    },
  );

  test('mixins, extensions and extension types retain their own headers', () {
    final mixin = declaration(
      'base mixin M<T> on B<T>, C implements I;',
    ) as MixinDeclaration;
    expect(mixin.isBase, isTrue);
    expect(mixin.onClause!.types.map((t) => t.text), ['B<T>', 'C']);
    expect(mixin.isSemicolonBody, isTrue);
    final extension = declaration(
      'extension X<T> on List<T> { T first()=>this[0]; }',
    ) as ExtensionDeclaration;
    expect(extension.name!.text, 'X');
    expect(extension.onType.text, 'List<T>');
    expect(extension.members.single, isA<MethodDeclaration>());
    expect(
      (declaration('extension on int;') as ExtensionDeclaration).name,
      isNull,
    );
    final type = declaration(
      'extension type const Id<T>.named(T value) implements Object;',
    ) as ExtensionTypeDeclaration;
    expect(type.isConst, isTrue);
    expect(type.primaryConstructorName!.text, 'named');
    expect(type.primaryParameters.text, '(T value)');
    expect(type.implementsClause!.types.single.text, 'Object');
  });

  test(
    'primary constructors and their bodies remain separate source nodes',
    () {
      final cls = declaration(
        'class const C<T>.named(final T value) extends B<T> { this : assert(value != null), super(value); }',
      ) as ClassDeclaration;
      expect(cls.isConst, isTrue);
      expect(cls.primaryConstructorName!.text, 'named');
      expect(
        cls.primaryParameters!.parameters.single.keyword,
        VariableKeyword.finalKeyword,
      );
      final body = cls.members.single as PrimaryConstructorBody;
      expect(body.initializers.first, isA<AssertInitializer>());
      expect(body.initializers.last, isA<SuperConstructorInitializer>());
      expect(body.body, isA<EmptyFunctionBody>());
      expect(
        (declaration('class C;') as ClassDeclaration).isSemicolonBody,
        isTrue,
      );
    },
  );

  test(
    'fields, methods, accessors and operators preserve written contracts',
    () {
      final cls = declaration(
        'class C { @A() static const int x=1,y=2; abstract int z; covariant Object value; int f<T>(T x)=>1; int get v=>1; set v(int x) {} int operator +(C other)=>1; int operator [](int i)=>i; void operator []=(int i,int value) {} external void native(); }',
      ) as ClassDeclaration;
      final field = cls.members.first as FieldDeclaration;
      expect(field.isStatic, isTrue);
      expect(field.variables.metadata.single.text, '@A()');
      expect(field.variables.declarations, hasLength(2));
      expect((cls.members[1] as FieldDeclaration).isAbstract, isTrue);
      expect((cls.members[2] as FieldDeclaration).isCovariant, isTrue);
      expect((cls.members[3] as MethodDeclaration).typeParameters!.text, '<T>');
      expect(cls.members[4], isA<GetterDeclaration>());
      expect(cls.members[5], isA<SetterDeclaration>());
      expect((cls.members[6] as OperatorDeclaration).op, DeclaredOperator.add);
      expect(
        (cls.members[7] as OperatorDeclaration).op,
        DeclaredOperator.indexRead,
      );
      expect(
        (cls.members[8] as OperatorDeclaration).op,
        DeclaredOperator.indexAssign,
      );
      expect((cls.members.last as MethodDeclaration).isExternal, isTrue);
    },
  );

  test(
    'constructors retain fields, assertions, super calls and redirections',
    () {
      final cls = declaration(
        'class C { const C(this.x); C.named():this(1); C.checked(int x):this.x=x, assert(x>0,"positive"), super.named(x); factory C.redirect()=p.D<int>.named; factory C.make()=>C(1); final int x; }',
      ) as ClassDeclaration;
      final first = cls.members[0] as ConstructorDeclaration;
      expect(first.isConst, isTrue);
      expect(
        first.parameters.parameters.single.prefix,
        ParameterPrefix.thisKeyword,
      );
      final redirect = cls.members[1] as ConstructorDeclaration;
      expect(
        redirect.initializers.single,
        isA<RedirectingConstructorInitializer>(),
      );
      final checked = cls.members[2] as ConstructorDeclaration;
      expect((checked.initializers[0] as FieldInitializer).hasThis, isTrue);
      expect(
        (checked.initializers[1] as AssertInitializer).message!.text,
        '"positive"',
      );
      expect(
        (checked.initializers[2] as SuperConstructorInitializer).name!.text,
        'named',
      );
      final factory = cls.members[3] as ConstructorDeclaration;
      final body = factory.body as FactoryRedirectBody;
      expect(factory.keyword, ConstructorKeyword.factoryKeyword);
      expect(body.name.map((n) => n.text), ['p', 'D']);
      expect(body.typeArguments!.text, '<int>');
      expect(body.constructorName!.text, 'named');
      expect(
        (cls.members[4] as ConstructorDeclaration).body,
        isA<ExpressionFunctionBody>(),
      );
    },
  );

  test(
    'abbreviated constructors retain keywords without invented class names',
    () {
      final cls = declaration(
        'class C { new(); new named(); const new other(); factory make()=D; }',
      ) as ClassDeclaration;
      final unnamed = cls.members[0] as ConstructorDeclaration;
      expect(unnamed.keyword, ConstructorKeyword.newKeyword);
      expect(unnamed.name, isEmpty);
      expect(
        (cls.members[1] as ConstructorDeclaration).name.single.text,
        'named',
      );
      expect((cls.members[2] as ConstructorDeclaration).isConst, isTrue);
      expect(
        (cls.members[3] as ConstructorDeclaration).name.single.text,
        'make',
      );
    },
  );

  test('enum constants keep metadata, instantiation and member separation', () {
    final value = declaration(
      'enum E<T> with M implements I { @A() a<int>(1), b<String>.named("x"); const E(T x); const E.named(T x); }',
    ) as EnumDeclaration;
    expect(value.constants, hasLength(2));
    expect(value.constants.first.metadata.single.text, '@A()');
    expect(value.constants.first.typeArguments!.text, '<int>');
    expect(value.constants.last.constructorName!.text, 'named');
    expect(value.hasMemberSeparator, isTrue);
    expect(value.members, hasLength(2));
    final primary = declaration(
      'enum E(final int value) { a(1), b(2) }',
    ) as EnumDeclaration;
    expect(primary.primaryParameters!.text, '(final int value)');
    expect(primary.hasMemberSeparator, isFalse);
  });

  test(
    'rejects invalid member combinations and preserves following declarations',
    () {
      for (final text in [
        'class C { static operator +(x)=>x; }',
        'class C { abstract void f(); }',
        'class C { covariant void f(){} }',
        'class C { factory C():x=1; int x; }',
        'class C { C() async {} }',
        'class C { C() sync* {} }',
        'class C { int operator &&(x)=>0; }',
        'class C { external void f() {} }',
        'class const C {}',
      ]) {
        expect(parse(text).hasErrors, isTrue, reason: text);
      }
      final result = parse(
        'class C { int x=; void next() {} } void after() {}',
      );
      expect(result.hasErrors, isTrue);
      expect(
        (result.node.members.first as ClassDeclaration).members.last,
        isA<MethodDeclaration>(),
      );
      expect(
        (result.node.members.last as TopLevelFunctionDeclaration).name.text,
        'after',
      );
      expect(
        declaration('external void Function();'),
        isA<TopLevelFunctionDeclaration>(),
      );
    },
  );

  test('malformed declarations terminate with valid source snapshots', () {
    final random = Random(5021);
    const pieces = [
      'class',
      'mixin',
      'enum',
      'extension',
      'type',
      'abstract',
      'base',
      'final',
      'const',
      'static',
      'external',
      'covariant',
      'C',
      'x',
      'int',
      'new',
      'factory',
      'this',
      'super',
      'assert',
      'operator',
      'get',
      'set',
      'extends',
      'implements',
      'with',
      'on',
      '(',
      ')',
      '{',
      '}',
      '[',
      ']',
      '<',
      '>',
      ';',
      ':',
      ',',
      '=',
      '=>',
      '@A',
      '1',
    ];
    for (var i = 0; i < 500; i++) {
      final content = List.generate(
        random.nextInt(40),
        (_) => pieces[random.nextInt(pieces.length)],
      ).join(' ');
      final text = i.isEven ? 'class C { $content }' : content;
      final result = parse(text);
      for (final node in walk(result.node)) {
        expect(node.start, inInclusiveRange(0, text.length));
        expect(node.end, inInclusiveRange(node.start, text.length));
        expect(node.source, same(result.node.source));
      }
    }
  });
}
