# hooks/lib/transcript.sh — Catalyst shared transcript reader.
# Sourced, not executed. No shebang, no set (caller owns shell options).
#
# sh_normalize_transcript <file> — emit one normalized JSON object per tool
# event to stdout: {type, name, input, content, ts, role}. Walks the real
# Claude Code shape (.message.content[]) AND passes through the legacy flat
# shape. Fails open: any error → no output, return 0.

sh_normalize_transcript() {
  local f="$1"
  [ -f "$f" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -c '
    def to_str:
      if   type=="string" then .
      elif type=="array"  then ([.[]? | (.text // .content // "") | select(type=="string")] | join("\n"))
      elif . == null      then ""
      else tostring end;
    if (.type=="tool_use" or .type=="tool_result") then
      { type, name:(.name // null), input:(.input // null),
        content:((.content // "") | to_str), ts:(.timestamp // null), role:(.role // null) }
    elif (.message.content? | type) == "array" then
      (.timestamp // null) as $ts | (.type // null) as $role |
      .message.content[]
      | select(.type=="tool_use" or .type=="tool_result")
      | { type, name:(.name // null), input:(.input // null),
          content:((.content // "") | to_str), ts:$ts, role:$role }
    else empty end
  ' "$f" 2>/dev/null || return 0
}
