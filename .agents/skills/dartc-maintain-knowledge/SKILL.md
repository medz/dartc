---
name: dartc-maintain-knowledge
description: Maintain dartc shared rules, current design documents and reusable skills during development, review and investigation. Trigger automatically on confirmed decisions, misleading delivery, recurring failures, missing methods or superseded guidance; also use for explicit documentation maintenance, not routine status logging.
---

# Maintain dartc Knowledge

Read repository AGENTS.md, the relevant [board card](../../docs/board.md), the [ownership index](../../docs/README.md#信息归属) and [maintenance flow](../../docs/workflow.md#自动知识维护). Shared docs and skills belong in the repository. Maintenance within an authorized task needs no separate request; follow that task’s commit/push authority. Updating guidance does not resume paused compiler work or authorize a production experiment.

## Decide what changes future work

Identify the concrete evidence or user decision, its version and scope, and the future action it should change. Separate specification, observed implementation, reproduced behavior and inference. A prototype's output is not default-product evidence; a rule violation is not proof that the rule was absent.

Find the existing owner before writing. Use the ownership index to update one canonical location and link its consumers rather than copying conclusions across them. Read the affected document set and skill routes, not just the paragraph that first exposed the problem.

## Update, replace or remove

Promote durable, actionable constraints to AGENTS only when supported by a user decision or a confirmed general contract. Put a method in a skill when its trigger, inputs, procedure and outcome are reusable. Put adopted design decisions in the owning current document; keep raw experiments outside the shared document set. Do not turn one example into a universal restriction or silently change the user's goal.

Replace conflicting active guidance and update references in the same change. Preserve necessary counterexamples in their tests or task acceptance and exact authoritative sources where they support the current contract. Remove superseded instructions, historical reports and duplicate reminders from current docs, then migrate or remove their incoming links; Git retains change history. Do not archive stale guidance inside the document set or leave local research and temporary paths as required evidence. Do not copy whole workspaces or create a new tracking system.

For skill evolution, inspect the actual failure: wrong trigger, missing inputs, incorrect method, noncompliance or insufficient implementation capability. For a recurring misleading delivery, identify the precise claim, contrary evidence and decision that allowed it through. Replace the faulty instruction or missing review routing with a specific check and rejection condition. Rules already existed in several dartc failures; adding a stronger warning without changing the next decision is not a correction.

Distinguish rules from machine enforcement. Put mechanically checkable invariants in the actual type/verifier/test owner when production changes are authorized; otherwise record that implementation gap in its existing task. Do not build a checklist that merely accepts the author's own success flag. Create or revise a skill when a needed reusable procedure is absent or inadequate, with a precise trigger, inputs, actions and observable outcome. Prefer repairing an existing skill over adding a duplicate. Keep automatic skill discovery unless requested otherwise; add scripts or references only for a concrete repeated need.

## Check and hand back

Validate changed TOML/YAML, skill frontmatter, links and instruction consistency across the affected document set. Verify that Git includes the shared docs and skills and that a clean checkout can resolve their required references; do not rely on ignored local files. Check for stale profile limits, task mappings, API sketches, completion claims and measurements instead of retaining them with a historical disclaimer. For substantive corrective review skills, use an independent agent with minimal context to evaluate a misleading or incomplete submission and an honestly bounded valid submission. Give raw artifacts and the skill, not the desired verdict or suspected defect. The review must reject unsupported completion without inventing faults or expanding the valid task. Treat supplied mock artifacts as workflow evaluation only. A structural check or mock evaluation does not establish production behavior; report unavailable evaluations explicitly.

Return what changed, what was removed, supporting evidence and remaining uncertainty. Update only the assigned card and do not declare another implementation accepted. The next comparable task should show less repeated work, waiting or error; if it does not, revise or retire the method rather than preserving ceremony.
