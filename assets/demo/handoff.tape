# handoff.tape — VHS script for the README demo GIF.
# Regenerate: bash assets/demo/build.sh  (sets up /tmp/catalyst-demo first)
# Every command below runs for real; the output is genuine handoff-render.py output.

Output assets/demo/handoff.gif

Set Shell bash
Set FontSize 17
Set Width 1180
Set Height 700
Set Padding 22
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms
Set PlaybackSpeed 1.0

# --- hidden setup: jump into the prepared demo repo ---
Hide
Type "cd /tmp/catalyst-demo && clear" Enter
Show

Sleep 600ms
Type "# Yesterday: you ran  /catalyst:handoff  before /compact." Enter
Sleep 900ms
Type "# It wrote a typed, validated brief — one per branch:" Enter
Sleep 700ms
Type "ls .claude/handoffs/" Enter
Sleep 1200ms
Type "jq '{key, resume, next: .state.next_acceptance_check}' .claude/handoffs/feat-jwt-expiry.json" Enter
Sleep 3000ms

Type "clear" Enter
Sleep 400ms
Type "# Today: fresh session. Claude remembers nothing." Enter
Sleep 900ms
Type "# Resume.  (/catalyst:handoff resume runs this for you:)" Enter
Sleep 800ms
Type "python3 scripts/handoff-render.py feat-jwt-expiry" Enter
Sleep 4500ms

Type "# Back to exactly where you left off — across the /compact wall." Enter
Sleep 2500ms
