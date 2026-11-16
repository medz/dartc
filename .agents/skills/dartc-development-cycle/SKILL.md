---
name: dartc-development-cycle
description: Implement or refactor an authorized dartc capability through its real compiler consumers, semantic contracts, cleanup and focused validation. Use for production changes across compiler domains, SDK patches or runtime behavior.
---

# dartc Development Cycle

Read repository AGENTS.md and the assigned [board card](../../docs/board.md). Check the current diff and actual revision after interruptions. A paused goal or documentation-only task does not authorize production work. The [workflow](../../docs/workflow.md) owns delegation, task transitions and knowledge routing.

## Establish behavior and ownership

State the observable behavior and violated contract before choosing a change. Trace declarations through callers and existing implementations to actual external leaves; an external public API does not prove its algorithm is missing. Consult the [runtime contract](../../docs/runtime.md) for std/runtime changes. Investigate a specific unresolved choice through the relevant owning source; current guidance must not depend on unpublished research.

Identify affected consumers, tests/fixtures, configuration, exports and replaced paths. Existing code and prior agent claims are evidence to challenge, not the architectural baseline. For a demonstrated contract/architecture failure, trace the original counterexample to its owner and state why the failure occurs. Compare continuing the patch route with repairing or replacing that boundary, including migration, cleanup and cost. Stop the affected workaround route if it only hides the failure; continue independent authorized work. Do not postpone root-cause reasoning until enough patches accumulate, nor require a large rewrite without a concrete causal reason.

Use the [foundation contract](../../docs/layout.md#基础能力先统一) when changing execution shapes. Preserve a default-config input where the required capability really executes and a relevant simplifiable input. Known types with runtime-varying values and genuinely polymorphic execution must not be conflated. Do not change the acceptance source, operation or configuration to make a failed obligation disappear. An explicitly authorized mitigation remains a mitigation until the original capability contract is met.

## Implement and remove replaced work

Reuse official Dart algorithms while supplying genuinely missing target operations. Keep runtime state and algorithms in ordinary Dart; machine layers own primitive representation, calling constraints, roots and PC locations. Preserve static obligations, order, exceptions, identity, termination and GC behavior.

Generated code must participate through actual calls, results and state. Replacing IR invalidates dependent facts; final emission consumes a closed program. Do not disguise missing compiler contracts as arbitrary external effects or extra unknown roots. Genuine dynamic behavior still needs a correct implementation.

Migrate consumers and remove replaced code, duplicate state and obsolete tests together. Check default Compiler/CLI behavior, not merely a new internal API. Do not add production switches or name exceptions to accommodate experiments.

## Validate the delivered contract

Select checks by changed contracts; reuse fixed fixtures and prebuilt assets when their inputs remain valid. Freeze relevant inputs before costly builds. Re-run a passed check only after changed inputs or a concrete new concern. Keep platform generation, emulation and actual execution distinct. Investigate specification/SDK disagreements instead of copying SDK output blindly.

Before reporting a measurement, identify the source revision/diff, compiler binary and fingerprint, SDK/resource inputs, target, configuration, workload, command and sampling scope. Verify behavior first. Keep altered-threshold or instrumented prototypes separate from default-product evidence; use existing benchmark tools before writing another harness. A stale executable cannot establish the current revision's behavior.

A test must detect a real contract failure. Where feasible, encode the demonstrated failure in the owning type/verifier or an affected contract test so the same invalid transition is rejected. Retain static, exception, GC and ABI regressions; remove assertions that only encode a migration path or repeat implementation structure. Additional tests or documentation alone do not prove the causal defect changed.

## Finish the capability

Before claiming delivery, closing the card or integrating as accepted work, obtain a non-author [delivery review](../dartc-review-delivery/SKILL.md) under the workflow gate. Supply the original requirements, exact revision/diff, fixed inputs/configuration, raw evidence and remaining gaps; do not supply only your preferred conclusion. Resolve blockers in the same task and recheck affected evidence. Neither passing local checks nor your own self-review substitutes for this gate.

Follow current commit/push authority. Report separately what changed, what was actually checked and what remains unproved. Withdraw completion or performance claims contradicted by evidence; preserve supported partial progress. A missing run is not a demonstrated runtime failure. Let independent authorized work continue without a round-wide barrier.

During implementation, validation and review, automatically apply [knowledge maintenance](../dartc-maintain-knowledge/SKILL.md) when a confirmed decision, failed assumption or reusable method changes future work. Update or create the needed rule or skill, remove obsolete guidance and migrate references in the same delivery; do not wait for a separate maintenance request or generate a diary without new information. After context compression, resume from the card, current diff and valid evidence instead of replaying old explanations or rebuilding unchanged assets.
