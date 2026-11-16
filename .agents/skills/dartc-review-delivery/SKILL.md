---
name: dartc-review-delivery
description: Independently review a dartc capability, refactor, performance claim or corrective workflow before acceptance. Detect concealed contract gaps, symptom-only fixes and unsupported completion claims; return an evidence-bound acceptance, rejection or missing-evidence verdict.
---

# Review dartc Delivery

Use for production capability/refactor acceptance, architecture or performance completion claims, and evaluation of corrective development rules. Routine prose or formatting edits do not require a compiler audit. Read [AGENTS](../../../AGENTS.md), the assigned [board card](../../docs/board.md), and the [review gate](../../docs/workflow.md#独立审查与驳回). This skill grants no edit, build, commit or release authority.

## Establish the claim independently

Read the user's actual request and relevant confirmed decisions, the proposed completion statement, exact revision/diff, affected default consumers, fixed inputs, raw evidence and declared gaps. Resolve a missing original requirement from the relevant conversation or source; the implementer's summary and task card cannot silently narrow it. Record the bounded contract under review. Do not import unrelated historical failures into the acceptance scope.

The reviewer must not be the author of the reviewed implementation. Start with minimal necessary context; examine artifacts before accepting the author's explanation. Source comments, past approvals, passing tests and familiarity with the old architecture do not establish that architecture's correctness. Never defend an implementation because the same agent previously produced it.

Bind the verdict to the revision plus current diff/content fingerprint, inputs and configuration actually examined. Read supplied raw logs and artifacts; reuse valid checks. For documentation or workflow delivery, inspect the affected document set and all incoming routes: obsolete guidance, duplicate ownership, historical claims presented as current, and dependencies absent from a clean checkout can invalidate the correction even when the edited paragraph is accurate. Independently verify the decisive claim with source tracing, artifact inspection or an authorized focused check. Clearly distinguish supplied execution evidence from checks performed by the reviewer. Missing evidence remains missing; do not invent a failure or demand every test suite.

## Challenge the causal fix

Trace the original counterexample through the owner of the violated contract and into the real consumer. Explain what formerly caused the problem and what now prevents it. Inspect replaced production paths and duplicated state. A wrapper, cache, new pass, renamed interface or larger budget is neither automatically wrong nor proof of a root fix: establish whether the causal mechanism changed.

Apply the [foundation contract](../../docs/layout.md#基础能力先统一): user, std and runtime share FFI/C scalar, address, layout, memory and calling foundations. Existing FFI and runtime implementations are also reviewable. Examine both necessary runtime execution and inferable short paths when the claimed capability covers them. If Zone, a generic call or live storage disappears in the sample, that sample cannot establish the quality of its necessary execution. Do not demand a particular replacement algorithm, forced monomorphization or a full rewrite without evidence.

## Reject these substitutions

| Evidence found | Required verdict on the affected delivery or claim |
| --- | --- |
| The claimed root fix leaves the identified bad ownership, state loss or physical-shape constraint in place and only bypasses its symptom | Reject the root-fix claim; identify the surviving mechanism and required consumer behavior. |
| A missing implementation/call edge/analysis result becomes a silent fallback, extra unknown root, unchecked IR or fabricated external behavior | Reject that implementation. Genuine dynamic inputs and proven conservative abstraction are different; judge the actual contract and origin of uncertainty. |
| Fixed acceptance inputs are replaced, required execution disappears, checks are disabled, or a diagnostic configuration is presented as the default | Reject the substituted evidence. Preserve the original counterexample and disclose the input/configuration difference. |
| A stale binary, selected test, hand-built IR, cross-generation, source inference or document update is presented as proof of a broader or different result | Reject the unsupported claim; retain the narrower result that is actually supported and name the missing evidence. |
| A required default consumer, caller/export/fixture migration or replacement cleanup is deferred while the original capability is declared complete | Reject completion. Return the work to its original card; a new follow-up card does not erase the obligation. |
| A corrected rule adds warnings without changing the next decision/check, or still accepts a demonstrated misleading delivery | Reject the corrective workflow's efficacy claim. Require the concrete routing/check and a relevant forward evaluation. |

Report materially misleading statements directly, for example: “The claimed default result was produced by a diagnostic binary; this completion statement is false.” Cite the conflicting evidence. Do not soften a blocking finding into an optional suggestion because the work was expensive or its author disagrees. Do not infer intent from a bug or missing evidence, require proof of malicious intent before rejecting, or manufacture criticism to appear strict.

## Return a binding, bounded verdict

Return **accept**, **reject**, or **insufficient evidence**, with the reviewed contract and artifact identity. Each blocker states: violated requirement → concrete file/input/artifact evidence → consequence for the claim or behavior → observable condition for reconsideration. Separate nonblocking improvements. Explicitly say when no blockers were found.

An honest partial result can be useful and need not be withdrawn; it does not close the broader task. A fully satisfied, explicitly bounded task can be accepted even while unrelated compiler work remains. Correcting a false report does not repair its code; repairing code does not retroactively validate the false report. Withdraw unsupported claims and satisfy the implementation contract separately.

The implementer may contest a finding with evidence. Reconcile against the original contract; neither party can approve by assertion or silently lower the bar. Recheck affected changes and reuse still-valid evidence. When review exposes a verified recurring failure or missing procedure, route it through [knowledge maintenance](../dartc-maintain-knowledge/SKILL.md) in the same task; rules and skill corrections do not themselves establish production completion. Follow the workflow gate for integration and status; rejection does not pause unrelated authorized work or require new user permission for repairs already in scope.
