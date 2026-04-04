const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const REPO_ROOT = path.resolve(__dirname, '..');
const STATUS_SH = path.join(REPO_ROOT, 'bin/lib/status.sh');
const JSON_BUILDER_SH = path.join(REPO_ROOT, 'bin/lib/json_builder.sh');

function runBash(script) {
  return execSync(`bash -c 'source "${STATUS_SH}" && source "${JSON_BUILDER_SH}" && ${script}'`, {
    cwd: REPO_ROOT,
    encoding: 'utf-8',
    timeout: 10000,
  }).trim();
}

function makeTmpSpecs(layout) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'trc-status-'));
  const specsDir = path.join(dir, 'specs');
  fs.mkdirSync(specsDir);

  for (const [name, files] of Object.entries(layout)) {
    const featureDir = path.join(specsDir, name);
    fs.mkdirSync(featureDir);
    for (const [fname, content] of Object.entries(files)) {
      fs.writeFileSync(path.join(featureDir, fname), content);
    }
  }
  return dir;
}

// ── status_detect_stage ──

describe('status_detect_stage', () => {
  it('returns "empty" for directory with no artifacts', () => {
    const dir = makeTmpSpecs({ 'TRI-1-test': {} });
    const result = runBash(`status_detect_stage "${dir}/specs/TRI-1-test"`);
    assert.equal(result, 'empty');
    fs.rmSync(dir, { recursive: true });
  });

  it('returns "specify" when only spec.md exists', () => {
    const dir = makeTmpSpecs({ 'TRI-1-test': { 'spec.md': '# Spec' } });
    const result = runBash(`status_detect_stage "${dir}/specs/TRI-1-test"`);
    assert.equal(result, 'specify');
    fs.rmSync(dir, { recursive: true });
  });

  it('returns "plan" when plan.md exists', () => {
    const dir = makeTmpSpecs({
      'TRI-1-test': { 'spec.md': '# Spec', 'plan.md': '# Plan' },
    });
    const result = runBash(`status_detect_stage "${dir}/specs/TRI-1-test"`);
    assert.equal(result, 'plan');
    fs.rmSync(dir, { recursive: true });
  });

  it('returns "tasks" when tasks.md has no checked items', () => {
    const dir = makeTmpSpecs({
      'TRI-1-test': {
        'spec.md': '# Spec',
        'plan.md': '# Plan',
        'tasks.md': '# Tasks\n- [ ] T001 Do something\n- [ ] T002 Do more',
      },
    });
    const result = runBash(`status_detect_stage "${dir}/specs/TRI-1-test"`);
    assert.equal(result, 'tasks');
    fs.rmSync(dir, { recursive: true });
  });

  it('returns "implement" when tasks.md has some checked items', () => {
    const dir = makeTmpSpecs({
      'TRI-1-test': {
        'tasks.md': '# Tasks\n- [x] T001 Done\n- [ ] T002 Not done',
      },
    });
    const result = runBash(`status_detect_stage "${dir}/specs/TRI-1-test"`);
    assert.equal(result, 'implement');
    fs.rmSync(dir, { recursive: true });
  });

  it('returns "done" when all tasks are checked', () => {
    const dir = makeTmpSpecs({
      'TRI-1-test': {
        'tasks.md': '# Tasks\n- [x] T001 Done\n- [x] T002 Also done',
      },
    });
    const result = runBash(`status_detect_stage "${dir}/specs/TRI-1-test"`);
    assert.equal(result, 'done');
    fs.rmSync(dir, { recursive: true });
  });

  it('returns "tasks" when tasks.md exists but has no task lines', () => {
    const dir = makeTmpSpecs({
      'TRI-1-test': { 'tasks.md': '# Tasks\nJust some text' },
    });
    const result = runBash(`status_detect_stage "${dir}/specs/TRI-1-test"`);
    assert.equal(result, 'tasks');
    fs.rmSync(dir, { recursive: true });
  });
});

// ── status_parse_dir_name ──

describe('status_parse_dir_name', () => {
  it('parses TRI-XX-slug pattern', () => {
    const id = runBash('status_parse_dir_name "TRI-24-feature-status" && echo "$STATUS_ID"');
    const name = runBash('status_parse_dir_name "TRI-24-feature-status" && echo "$STATUS_NAME"');
    assert.equal(id, 'TRI-24');
    assert.equal(name, 'feature-status');
  });

  it('parses NNN-slug pattern', () => {
    const id = runBash('status_parse_dir_name "001-headless-mode" && echo "$STATUS_ID"');
    const name = runBash('status_parse_dir_name "001-headless-mode" && echo "$STATUS_NAME"');
    assert.equal(id, '001');
    assert.equal(name, 'headless-mode');
  });

  it('handles freeform dir name with no ID', () => {
    const id = runBash('status_parse_dir_name "my-feature" && echo "$STATUS_ID"');
    const name = runBash('status_parse_dir_name "my-feature" && echo "$STATUS_NAME"');
    assert.equal(id, '');
    assert.equal(name, 'my-feature');
  });

  it('handles multi-digit issue numbers', () => {
    const id = runBash('status_parse_dir_name "PROJ-1234-big-feature" && echo "$STATUS_ID"');
    const name = runBash('status_parse_dir_name "PROJ-1234-big-feature" && echo "$STATUS_NAME"');
    assert.equal(id, 'PROJ-1234');
    assert.equal(name, 'big-feature');
  });
});

// ── status_progress_for_stage ──

describe('status_progress_for_stage', () => {
  it('returns correct percentages for all stages', () => {
    assert.equal(runBash('status_progress_for_stage empty'), '0');
    assert.equal(runBash('status_progress_for_stage specify'), '25');
    assert.equal(runBash('status_progress_for_stage plan'), '50');
    assert.equal(runBash('status_progress_for_stage tasks'), '75');
    assert.equal(runBash('status_progress_for_stage implement'), '80');
    assert.equal(runBash('status_progress_for_stage done'), '100');
  });

  it('returns 0 for unknown stage', () => {
    assert.equal(runBash('status_progress_for_stage "nonsense"'), '0');
  });
});
