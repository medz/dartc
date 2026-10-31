import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('Exception syntax', () {
    test('retains ordered catch forms, explicit parameters, and finally', () {
      final f = SyntaxFixture(
        'try {} on Error catch (e, s) { rethrow; } on Other {} catch (other) {} finally {}',
      );
      final rethrowStatement = RethrowStatement(
        source: f.source,
        start: f.at('rethrow'),
        end: f.at(';') + 1,
      );
      final clauses = [
        CatchClause(
          source: f.source,
          start: f.at('on Error'),
          end: f.at('} on', f.at('rethrow')) + 1,
          exceptionType: f.type('Error'),
          exceptionParameter: f.id('e', f.at('(e')),
          stackTraceParameter: f.id('s', f.at(', s')),
          body: BlockStatement(
            source: f.source,
            start: f.at('{ rethrow'),
            end: f.at('} on', f.at('rethrow')) + 1,
            statements: [rethrowStatement],
          ),
        ),
        CatchClause(
          source: f.source,
          start: f.at('on Other'),
          end: f.at('{}', f.at('on Other')) + 2,
          exceptionType: f.type('Other'),
          body: f.emptyBlock(f.at('{}', f.at('on Other'))),
        ),
        CatchClause(
          source: f.source,
          start: f.at('catch (other)'),
          end: f.at(' finally'),
          exceptionParameter: f.id('other'),
          body: f.emptyBlock(f.at('{}', f.at('catch (other)'))),
        ),
      ];
      final node = TryStatement(
        source: f.source,
        start: 0,
        end: f.source.length,
        body: f.emptyBlock(4),
        catchClauses: clauses,
        finallyBlock: f.emptyBlock(f.at('{}', f.at('finally'))),
      );
      clauses.clear();
      checkTree(node);
      expect(node.catchClauses.map((c) => c.exceptionType?.text), [
        'Error',
        'Other',
        null,
      ]);
      expect(node.catchClauses[1].exceptionParameter, isNull);
      expect(node.catchClauses.last.stackTraceParameter, isNull);
      expect(
        walk(node).whereType<RethrowStatement>().single,
        same(rethrowStatement),
      );
      expect(node.childAt(node.childCount - 1), same(node.finallyBlock));
      expect(() => node.catchClauses.clear(), throwsUnsupportedError);
    });

    test(
      'does not insert omitted handlers, finally blocks, types, or parameters',
      () {
        final f = SyntaxFixture('try {} catch (e) {}');
        final clause = CatchClause(
          source: f.source,
          start: f.at('catch'),
          end: f.source.length,
          exceptionParameter: f.id('e', f.at('(e')),
          body: f.emptyBlock(f.source.length - 2),
        );
        final node = TryStatement(
          source: f.source,
          start: 0,
          end: f.source.length,
          body: f.emptyBlock(4),
          catchClauses: [clause],
        );
        checkTree(node);
        expect(node.finallyBlock, isNull);
        expect(clause.exceptionType, isNull);
        expect(clause.stackTraceParameter, isNull);
        expect(node.childCount, 2);
        final g = SyntaxFixture('try {} finally {}');
        final onlyFinally = TryStatement(
          source: g.source,
          start: 0,
          end: g.source.length,
          body: g.emptyBlock(4),
          finallyBlock: g.emptyBlock(g.source.length - 2),
        );
        checkTree(onlyFinally);
        expect(onlyFinally.catchClauses, isEmpty);
        expect(onlyFinally.childAt(1), same(onlyFinally.finallyBlock));
      },
    );

    test(
      'rejects swapped blocks, stale clauses, and parameter order errors',
      () {
        final f = SyntaxFixture('try {} catch(e, s) {} finally {}');
        final old = SyntaxFixture(f.source.text);
        final clause = CatchClause(
          source: f.source,
          start: f.at('catch'),
          end: f.at(' finally'),
          exceptionParameter: f.id('e', f.at('(e')),
          stackTraceParameter: f.id('s', f.at(', s')),
          body: f.emptyBlock(f.at('{}', f.at('catch'))),
        );
        expect(
          () => TryStatement(
            source: f.source,
            start: 0,
            end: f.source.length,
            body: f.emptyBlock(4),
            catchClauses: [clause],
            finallyBlock: f.emptyBlock(4),
          ),
          throwsArgumentError,
        );
        expect(
          () => TryStatement(
            source: old.source,
            start: 0,
            end: old.source.length,
            body: old.emptyBlock(4),
            catchClauses: [clause],
          ),
          throwsArgumentError,
        );
        expect(
          () => CatchClause(
            source: f.source,
            start: f.at('catch'),
            end: f.at(' finally'),
            exceptionParameter: f.id('s', f.at(', s')),
            stackTraceParameter: f.id('e', f.at('(e')),
            body: f.emptyBlock(f.at('{}', f.at('catch'))),
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
