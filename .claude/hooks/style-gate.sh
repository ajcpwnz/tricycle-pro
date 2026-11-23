#!/bin/bash
# PreToolUse(Write|Edit|Bash|tracker issue and comment tools): persisted prose
# passes the ASD-STE100 linter before it lands.
#
# Checked: Markdown written with Write or Edit, `gh pr create|edit` bodies, and
# tracker issue and comment text. Commit messages are not checked. Only the
# added text is linted, so old prose in a file never blocks an edit.
#
# Text that agents read (blocks, agents, skills, commands, CLAUDE.md, AGENTS.md,
# the constitution) gets the Strict mode: one word for one meaning is enforced.
# Other prose gets the STE-flavored mode, without that rule.
#
# Fails open: without python3, or without the asd-ste100 plugin installed and
# enabled, the hook exits 0 and changes nothing. TRC_STYLE_GATE=0 turns it off.

[ "${TRC_STYLE_GATE:-1}" = "0" ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
exec python3 -I - "$CFG" 3<&0 <<'PY'
import json, os, re, shlex, subprocess, sys

cfg = sys.argv[1]
PLUGIN = "asd-ste100@asd-ste100-skill"
STRICT = re.compile(r"(^|/)(\.trc/blocks|\.claude/(agents|skills|commands)|core/(blocks|agents|skills|commands))/"
                    r"|(^|/)(CLAUDE|AGENTS)\.md$|(^|/)constitution[^/]*\.md$")
# A command segment that starts a PR write. Text that only mentions
# one, inside a string or a script, does not count.
SEG = r"(?:^|[;&|(]|\$\()\s*"
PR = re.compile(SEG + r"gh\s+pr\s+(?:create|edit)\b")

def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None

def linter():
    settings = load(os.path.join(cfg, "settings.json")) or {}
    if (settings.get("enabledPlugins") or {}).get(PLUGIN) is not True:
        return None
    installed = (load(os.path.join(cfg, "plugins", "installed_plugins.json")) or {}).get("plugins", {})
    for entry in installed.get(PLUGIN) or []:
        path = os.path.join(entry.get("installPath", ""), "scripts", "ste-lint.py")
        if os.path.isfile(path):
            return path
    return None

def added_lines(old, new):
    seen = set(old.splitlines())
    return "\n".join(line for line in new.splitlines() if line not in seen)

def read(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return ""

def prose_path(path):
    if not path.lower().endswith((".md", ".mdx")):
        return False
    real = os.path.realpath(path)
    return not real.startswith(os.path.realpath(cfg) + os.sep)

def bash_texts(cmd, cwd):
    if not PR.search(cmd):
        return []
    # A heredoc is the body only when its opening line is the PR command itself:
    # `gh pr create --body-file - <<EOF`.
    texts = []
    for m in re.finditer(r"([^\n]*)<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n(.*?)\n\s*\2\b", cmd, re.S):
        if PR.search(m.group(1)):
            texts.append(m.group(3))
    if texts:
        return texts
    cmd_lines = [l for l in cmd.splitlines() if PR.search(l)]
    if not cmd_lines:
        return []
    cmd = "\n".join(cmd_lines)
    try:
        words = shlex.split(cmd)
    except ValueError:
        return []
    flags_text, flags_file = ("-b", "--body"), ("--body-file",)
    for i, w in enumerate(words):
        nxt = words[i + 1] if i + 1 < len(words) else ""
        if w in flags_text:
            texts.append(nxt)
        elif w in flags_file and nxt not in ("-", ""):
            texts.append(read(os.path.join(cwd, nxt)))
        else:
            for f in flags_text + flags_file:
                if w.startswith(f + "="):
                    val = w.split("=", 1)[1]
                    texts.append(val if f in flags_text else read(os.path.join(cwd, val)))
    return texts

def texts_for(payload):
    tool = payload.get("tool_name", "")
    inp = payload.get("tool_input") or {}
    cwd = payload.get("cwd") or os.getcwd()
    if tool in ("Write", "Edit", "MultiEdit"):
        path = inp.get("file_path", "")
        if not prose_path(path):
            return [], False
        strict = bool(STRICT.search(path))
        if tool == "Write":
            return [added_lines(read(path), inp.get("content", ""))], strict
        edits = inp.get("edits") or [inp]
        return [added_lines(e.get("old_string", ""), e.get("new_string", "")) for e in edits], strict
    if tool == "Bash":
        return bash_texts(inp.get("command", ""), cwd), False
    if re.search(r"__(save|create)_(issue|comment)$", tool):
        return [inp.get(k, "") for k in ("description", "body") if inp.get(k)], False
    return [], False

try:
    payload = json.load(os.fdopen(3))
    lint = linter()
    texts, strict = texts_for(payload) if lint else ([], False)
    texts = [t for t in texts if t and t.strip()]
    mode = [] if strict else ["--disable", "synonym-rotation"]
    findings = []
    for t in texts:
        r = subprocess.run(["python3", "-I", lint, "--json"] + mode,
                           input=t, capture_output=True, text=True, timeout=20)
        for v in json.loads(r.stdout).get("violations", []):
            if v.get("level") != "advisory":
                findings.append(v)
except Exception:
    sys.exit(0)

if findings:
    lines = "\n".join(f"  - {v['rule']}: \"{v.get('match', '')}\" — {v.get('message', '')}" for v in findings[:12])
    reason = ("BLOCKED: this prose breaks ASD-STE100 rules (asd-ste100 linter):\n" + lines +
              "\n\nRewrite only the flagged sentences, then retry. Follow the ste-short skill: "
              "one fact per sentence (20 words for steps, 25 for descriptions), plain verbs, "
              "no phrasal verbs, no nominalizations, no marketing words, no semicolons. "
              "Keep every hedge, number, negation and identifier exact.")
    print(json.dumps({"decision": "block", "reason": reason}))
sys.exit(0)
PY
