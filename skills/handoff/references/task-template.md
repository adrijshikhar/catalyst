# Task: <short task name>

## Task

<Objective and all agreed requirements for this selected task. Include relevant
conversation decisions, rationale and rejected approaches that are not already
in referenced files. Replace every angle-bracket placeholder before delivery.>

Scope: <allowed changes and explicit exclusions>

Read first:
- <absolute file path or repository-relative path, with its purpose>

Dependencies and known risks: <required artifacts, upstream work and unresolved
questions; state explicitly when no dependencies are required>

## Workspace

- Repository / task directory: <absolute path; identify the repository for cross-machine use>
- Source worktree: <absolute path>
- Base commit: <full commit SHA, or not applicable outside Git>
- Selected strategy: <separate worktree and branch, or current workspace>
- Required uncommitted changes: <specific files and how to obtain them, or none>

Read the repository's agent instructions before editing. Verify the repository,
base commit and dependencies against the actual filesystem. Paths recorded on
another machine must be resolved locally. If required material is inaccessible,
report blocked with the exact missing dependency instead of guessing.

For a separate workspace, create a new Git worktree and branch from the recorded
base before editing. Choose unused names and record the actual path and branch
in Completion. Never reset an existing branch, clean another worktree or assume
uncommitted source changes are in the base commit. Resolve any required dirty
changes before starting. For the current workspace, inspect its working changes
and preserve other work; report conflicting concurrent edits before proceeding.

## Acceptance checklist

- [ ] <Concrete outcome and its verification command or evidence>
- [ ] <Additional agreed outcome, if required; remove unused items>

## Return instructions

This is a scoped task handed off from an ongoing session. Catalyst is not required
to execute it. Follow the task within your host's permissions and repository
instructions. Do not expand scope or merge into the originating branch.

Preserve all text before `## Completion`, including the original acceptance
checklist. You own the Completion section while working. When done or blocked,
update that section with:

- **Status:** complete, partial or blocked. Complete requires evidence for every
  acceptance item; unrun or failing checks remain explicitly unresolved.
- **Workspace:** actual path, branch and starting commit, if using Git.
- **Changes/result:** files changed and concrete outcomes; for read-only tasks,
  report findings and their sources.
- **Checklist results:** repeat each original item with its result and evidence.
- **Verification:** commands actually run, their outcomes and any unrun checks.
- **Delivery:** resulting commit SHAs, or the exact worktree and uncommitted files.
  Do not assume changes are committed, pushed, merged or available elsewhere.
- **Remaining issues:** blockers, risks and incomplete requirements.
- **Integration:** which changes to review/apply and any prerequisites. Explain
  conflicts or dependencies without applying them to the originating branch.

Do not write a session checkpoint or project narrative for this task's return.
Return only a short message for the user to pass to the originating agent,
substituting this task file's real absolute path:

> Read the Completion section in `<absolute-task-file>`. Review the referenced
> changes and evidence against the original acceptance checklist, then report
> whether the task is ready to integrate and what remains unresolved.

The originating agent reviews the actual artifacts before integration. A
completion statement is a report, not independent proof that changes are correct.

## Completion
