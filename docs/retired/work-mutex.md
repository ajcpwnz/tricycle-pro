# Retired: work mutex

Removed from the polst trc copy on 2026-11-23. Kept as input for a successor.

**Delete this file, and `docs/retired/` if empty, in the same change that ships the successor ("mutex 2.0").**

- Full source: `git show c3f6b0f8d:<path>` in polst for `.claude/hooks/lib/mutex.sh`, `.claude/hooks/guard-authoring.sh` (rules mutex-required, mutex-precedes-work, mutex-quality, mutex-append-needs-consent), `.claude/hooks/guard-push.sh` (mutex-open), `.claude/hooks/stop-finish.sh` (gate a + HALT/DONE last-line markers), `.trc/blocks/{tasks,implement}/work-mutex.md`, `.trc/templates/mutex-template.md`, tests `.claude/hooks/__tests__/{mutex-append-consent,pol-2512}.test.sh`.
- Design: `.trc/mutex.md` (gitignored, per worktree), line 1 `branch: <name>`, items `- [ ] ID | AREA | ACTION | EVIDENCE: ...`, AREA in code|test|setup|data|docs|verify|deploy. Written at trc.tasks from the request, before the first non-doc edit. Creation needs >=3 AREAs, a verify item, nothing closed. Vague evidence ("it works", "passes") refused. New open items mid-work need `AUTHORISED:` or `DEFECT-IN-DIFF:`.
- Enforcement: PreToolUse Write/Edit blocked non-doc edits without a governing mutex once a trc flow ran (branch adds specs/*/spec.md). Mutex creation after a non-doc edit in the transcript was refused. PreToolUse Bash refused push/PR while items were open. Stop hook blocked stop while items were open, escapable only by a last line `HALT: destructive-consent|blocking-input|push-approval` or `DONE: <reason>`.
- Why it failed (2026-11-23): every gate trusted a file or token the agent writes. Bypasses: stop twice (`stop_hook_active` passes the 2nd stop), tick `[x]` without evidence (only checkbox counted), edit `branch:` line (mismatch = absent), delete the file, emit a marker line. A successor must gate on facts the agent does not author (git/remote state, CI results, executed commands), not self-reports.
