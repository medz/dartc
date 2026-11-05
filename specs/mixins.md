# Mixin application lowering

The lowerer processes each mixin application with the existing resolved AST lowerer. It changes no IR instruction, verifier contract, or fixture runtime behavior.

`C extends B with M, N` has the ordinary class chain `C -> application(N) -> application(M) -> B`. Each application implements its source mixin interface and owns concrete function targets and fields. A pure mixin declaration contains its nominal interface and static members; a mixin class also retains its ordinary class bodies.

## Supported scope

- Non-generic mixin declarations and applications, including multiple and repeated applications, overrides, nominal interfaces, defaults, tearoffs, closures, and cross-library private selectors.
- Independent mutable, final and late field slots per application. Existing getter/setter and late-initializer lowering is reused. An ordinary initializer initializes eager fields before delegating to the preceding application, preserving derived-first initialization order.
- Non-generic `on` constraints and lexical `super` member references. Each application stores the existing implementation plan's prefix during compilation. Bodies and escaping closures bind super to that prefix, not to the most-derived receiver.
- Analyzer-generated named mixin application constructors, including named parameters and defaults. Each application forwards through ordinary initializers to its immediate superclass.
- Mixin classes without their own mixin applications, including application-specific Object member bindings.

## Explicit restrictions

Generic mixin declarations, generic own methods, generic application classes, generic on constraints and direct generic bases remain unsupported. So do source abstract members, source implemented interfaces, nested mixin class applications, application constants, and applications requiring new typed noSuchMethod forwarders or additional covariance checks. All source mixins and non-Object superclass declarations must be in the input batch.

A mixin `on B` includes B in its nominal interface hierarchy, as confirmed by an SDK test with an unrelated class implementing the mixin interface. Its application body receives the concrete application type, whose existing superclass hierarchy also supplies the lexical super implementation. General generic receiver environments and additional covariance provenance still require separate work.

## Cost and contracts

The same AST is lowered once per application. Generated IR bodies and lexical closures therefore grow with application count, but compiler implementation and runtime state do not need shared-body aliases, field-slot mappings, or captured dynamic application origins. Each generated body is checked by the existing IR verifier against its actual owner.

Tests: [basic applications](../test/lowering/mixins_test.dart), [fields and lexical super](../test/lowering/mixin_application_state_test.dart), [unsupported boundaries](../test/lowering/mixins_unsupported_test.dart).
