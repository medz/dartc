import '../../frontend/lowering/fixtures/typed_forwarders.dart' as typed;
import '../../frontend/lowering/fixtures/typed_forwarders_private_use.dart'
    as inherited;
import '../../frontend/lowering/fixtures/private_forwarders.dart' as private;
import '../../frontend/lowering/fixtures/private_forwarders_child.dart'
    as child;
import '../../frontend/lowering/fixtures/forwarder_result_casts.dart'
    as results;
import '../../frontend/lowering/fixtures/covariant_forwarder_sources.dart'
    as covariance;
import 'extension_types.dart' show observe;

void main(List<String> args) {
  switch (args.single) {
    case 'typed':
      for (final (name, run, count) in <(String, Object? Function(int), int)>[
        ('forwardForms', typed.forwardForms, 14),
        ('forwardGenerics', typed.forwardGenerics, 6),
        ('forwardVoid', typed.forwardVoid, 7),
        ('forwardInheritance', typed.forwardInheritance, 8),
      ]) {
        for (var form = 0; form < count; form++) {
          observe(name, () => run(form), form);
        }
      }
      for (var form = 0; form < 10; form++) {
        for (final input in <Object?>[7, 'bad', null]) {
          observe('forwardFailures', () => typed.forwardFailures(form, input), [
            form,
            input,
          ]);
        }
      }
      for (var form = 0; form < 5; form++) {
        for (var operation = 0; operation < 5; operation++) {
          observe(
            'forwardImmutability',
            () => typed.forwardImmutability(form, operation),
            [form, operation],
          );
        }
      }
      observe('forwardSuperOrder', typed.forwardSuperOrder);
    case 'results':
      final inputs = <Object?>[null, 7, 'text', (1, 'record')];
      for (var form = 0; form < 6; form++) {
        for (var index = 0; index < inputs.length; index++) {
          observe('forwardResult', () {
            final value = results.forwardResult(form, inputs[index]);
            return value is (int, String) ? [value.$1, value.$2] : value;
          }, [form, index]);
        }
      }
    case 'covariance':
      for (final (name, run, count)
          in <(String, Object? Function(int, Object?), int)>[
            ('forwardCovariance', typed.forwardCovariance, 7),
            ('forwardNamedCovariance', typed.forwardNamedCovariance, 4),
            ('forwardRepeatedCovariance', typed.forwardRepeatedCovariance, 6),
            ('sourceCovariance', covariance.sourceCovariance, 11),
            ('ownSourceCovariance', covariance.ownSourceCovariance, 11),
            (
              'transitiveSourceCovariance',
              covariance.transitiveSourceCovariance,
              5,
            ),
          ]) {
        for (var form = 0; form < count; form++) {
          for (final input in <Object?>[7, 1.5, 'bad', null]) {
            observe(name, () => run(form, input), [form, input]);
          }
        }
      }
    case 'private':
      for (var kind = 0; kind < 3; kind++) {
        for (var form = 0; form < 23; form++) {
          for (final input in <Object?>[7, 1.5, 'bad', null]) {
            observe(
              'privateForms',
              () => private.privateForms(kind, form, input),
              [kind, form, input],
            );
          }
        }
      }
      for (var form = 0; form < 4; form++) {
        observe('privateSecond', () => private.privateSecond(form), form);
      }
      observe('privateOwn', private.privateOwn);
      for (var kind = 0; kind < 2; kind++) {
        for (final form in [0, 1, 2, 15, 16, 18, 20]) {
          for (final input in <Object?>[7, 1.5, 'bad', null]) {
            observe(
              'privateReplacement',
              () => private.privateReplacement(kind, form, input),
              [kind, form, input],
            );
          }
        }
        for (var form = 0; form < 4; form++) {
          observe(
            'privateUnchanged',
            () => private.privateUnchanged(kind, form),
            [kind, form],
          );
        }
      }
      for (final (name, run, count)
          in <(String, Object? Function(int, Object?), int)>[
            ('privateCovariance', private.privateCovariance, 3),
            ('privateNamed', private.privateNamed, 4),
          ]) {
        for (var form = 0; form < count; form++) {
          for (final input in <Object?>[7, 1.5, 'bad', null]) {
            observe(name, () => run(form, input), [form, input]);
          }
        }
      }
      for (final form in [0, 1, 2, 15, 16, 18]) {
        for (final input in [7, 'bad']) {
          observe(
            'privateThrowReuse',
            () => child.privateThrowReuse(form, input),
            [form, input],
          );
        }
      }
      for (var form = 0; form < 3; form++) {
        observe(
          'privateCompatible',
          () => private.privateCompatible(form),
          form,
        );
        for (final tearoff in [false, true]) {
          observe(
            'forwardPrivateInheritance',
            () => inherited.forwardPrivateInheritance(form, tearoff),
            [form, tearoff],
          );
        }
      }
      for (var form = 0; form < 6; form++) {
        observe(
          'privateErrorFactory',
          () => private.privateErrorFactory(form),
          form,
        );
      }
      observe('privatePublicBody', private.privatePublicBody);
  }
}
