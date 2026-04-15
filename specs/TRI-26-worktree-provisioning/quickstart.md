# Quickstart: Verifying `--provision-worktree`

**Feature**: TRI-26-worktree-provisioning
**Audience**: Anyone implementing or reviewing the feature.

This quickstart is a throwaway, end-to-end demonstration of the new `--provision-worktree` flag. It is runnable as-is on macOS or Linux with `bash`, `git`, and `npm` installed.

## 0. Prerequisites

```bash
command -v git npm bash
git --version   # any recent version is fine
npm --version   # any recent version is fine
```

## 1. Seed a throwaway project

```bash
rm -rf /tmp/prov-demo && mkdir /tmp/prov-demo && cd /tmp/prov-demo
git init -q
git commit --allow-empty -q -m "init"
npm init -y >/dev/null
```

## 2. Drop in the `.trc/` toolchain

Copy the TRI-26 branch's `.trc/` into the throwaway repo:

```bash
cp -r /Users/alex/projects/tricycle-pro-TRI-26-worktree-provisioning/.trc .trc
```

(In real usage, the user would have run `tricycle init` — this shortcut is fine for the quickstart.)

## 3. Configure worktree provisioning

Create `tricycle.config.yml`:

```yaml
project:
  name: "prov-demo"
  type: "single-app"
  package_manager: "npm"
  base_branch: "main"

branching:
  style: feature-name

workflow:
  blocks:
    specify:
      enable:
        - worktree-setup

worktree:
  enabled: true
  setup_script: scripts/worktree-setup.sh
  env_copy:
    - .env.local
```

Create the setup script:

```bash
mkdir -p scripts
cat > scripts/worktree-setup.sh <<'EOF'
#!/usr/bin/env bash
set -e
echo "[setup] running in $(pwd)"
touch .env.local
echo "LOCAL_KEY=abc" > .env.local
EOF
chmod +x scripts/worktree-setup.sh
git add -A && git commit -q -m "seed demo"
```

## 4. Run `create-new-feature.sh --provision-worktree`

```bash
.trc/scripts/bash/create-new-feature.sh \
    "Add demo feature" \
    --json \
    --style feature-name \
    --short-name demo-feature \
    --provision-worktree
```

## 5. Verify the happy path

The JSON output should contain `WORKTREE_PATH`:

```json
{"BRANCH_NAME":"demo-feature","SPEC_FILE":"/tmp/prov-demo-demo-feature/specs/demo-feature/spec.md","FEATURE_NUM":"","WORKTREE_PATH":"/tmp/prov-demo-demo-feature"}
```

Then, inside the worktree:

```bash
cd /tmp/prov-demo-demo-feature
ls node_modules | head -1      # should exist (empty is OK — `npm init` had no deps)
ls -la .env.local               # should exist
ls specs/demo-feature/spec.md   # should exist (from template)
ls .trc/blocks/                 # .trc/ was copied in
```

All four should pass.

## 6. Verify the negative paths

### 6a. Missing `env_copy` path (exit 15)

Point `env_copy` at a file the setup script does not create:

```bash
cd /tmp/prov-demo
# edit tricycle.config.yml: worktree.env_copy: [.env.nonexistent]
# commit, delete worktree, rerun step 4
```

Expected:

```text
Error: worktree.env_copy paths missing after setup:
  - .env.nonexistent
```

Exit code: `15`.

### 6b. Setup script exits non-zero (exit 14)

Edit `scripts/worktree-setup.sh` to `exit 1` and rerun. Expected: `Error: worktree.setup_script 'scripts/worktree-setup.sh' exited 1` with exit `14`.

### 6c. Setup script missing (exit 12)

`rm scripts/worktree-setup.sh` and rerun. Expected: `Error: worktree.setup_script 'scripts/worktree-setup.sh' does not exist in worktree root` with exit `12`.

### 6d. Package manager install fails (exit 11)

Add a bogus dep to `package.json` (e.g., `"deps": { "does-not-exist-xyz": "1.0.0" }`) and rerun. Expected: `Error: 'npm install' failed with exit <N> in /tmp/prov-demo-demo-feature` with exit `11`.

## 7. Verify backward compatibility

```bash
cd /tmp/prov-demo-plain && git init -q && git commit --allow-empty -q -m "init"
cp -r /Users/alex/projects/tricycle-pro-TRI-26-worktree-provisioning/.trc .trc
.trc/scripts/bash/create-new-feature.sh "plain feature" --json --style feature-name --short-name plain
```

No `--provision-worktree`. Expected: script behaves exactly as it does today — creates branch, checks it out in the main checkout, creates `specs/plain/spec.md`, prints JSON without `WORKTREE_PATH`. This is the SC-002 regression check.

## 8. Cleanup

```bash
rm -rf /tmp/prov-demo /tmp/prov-demo-* 2>/dev/null || true
```
