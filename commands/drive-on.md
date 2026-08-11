---
description: Turn drive mode ON — finish-or-surface discipline, live task tracking, documentation, succinct replies (until /drive-off)
allowed-tools: Bash(touch:*)
---

!`touch "$HOME/.claude/drive-mode"`

Drive mode has just been switched ON (the flag file was created; a UserPromptSubmit hook injects the drive contract into every prompt from the next one onward). Confirm to the user in two lines: drive mode is on for this and all future sessions until they run /drive-off, and every task will now be driven through blockers to a verified finish, tracked live in the task list, documented in the repo, and reported succinctly. Do not treat this toggle itself as a task.
