const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const REPO_ROOT = path.resolve(__dirname, '..');
const CHAIN = path.join(REPO_ROOT, 'core/scripts/bash/chain-run.sh');
const CHAIN_RUNS_DIR = path.join(REPO_ROOT, 'specs/.chain-runs');

function run(args, env = {}) {
  try {
    const out = execSync(`bash "${CHAIN}" ${args}`, {
      cwd: REPO_ROOT,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout: 10000,
      env: { ...process.env, ...env },
    });
    return { exit: 0, stdout: out.trim(), stderr: '' };
  } catch (e) {
    return { exit: e.status, stdout: (e.stdout || '').toString().trim(), stderr: (e.stderr || '').toString().trim() };
  }
}

function cleanupRun(runId) {
  if (!runId) return;
  const dir = path.join(CHAIN_RUNS_DIR, runId);
  if (fs.existsSync(dir)) fs.rmSync(dir, { recursive: true, force: true });
}

describe('chain-run.sh init + get', () => {
  const created = [];
  after(() => {
    for (const id of created) cleanupRun(id);
  });

  it('init happy path creates state.json with correct schema', () => {
    const r = run(`init --ids '["TRI-100","TRI-101"]' --ids-raw 'TRI-100..TRI-101'`);
    assert.equal(r.exit, 0, `init failed: ${r.stderr}`);
    const j = JSON.parse(r.stdout);
    assert.ok(j.run_id);
    assert.ok(j.state_path);
    assert.equal(j.brief_path, null);
    created.push(j.run_id);

    const state = JSON.parse(run(`get --run-id ${j.run_id}`).stdout);
    assert.equal(state.run_id, j.run_id);
    assert.equal(state.status, 'in_progress');
    assert.equal(state.current_index, 0);
    assert.deepEqual(state.ticket_ids, ['TRI-100', 'TRI-101']);
    assert.equal(state.tickets['TRI-100'].status, 'not_started');
    assert.equal(state.tickets['TRI-101'].status, 'not_started');
    assert.equal(state.tickets['TRI-100'].branch, null);
    assert.equal(state.tickets['TRI-100'].commit_sha, null, 'TRI-30: commit_sha field initialized to null');
    assert.equal(state.tickets['TRI-101'].commit_sha, null);
    assert.ok(state.created_at);
    assert.equal(state.epic_brief_path, null);
  });

  it('init with --brief copies the file into the run dir', () => {
    const tmp = path.join(os.tmpdir(), `brief-${Date.now()}.md`);
    fs.writeFileSync(tmp, '# Shared epic brief\nTest content');
    try {
      const r = run(`init --ids '["TRI-200"]' --brief ${tmp}`);
      assert.equal(r.exit, 0);
      const j = JSON.parse(r.stdout);
      created.push(j.run_id);
      assert.ok(j.brief_path);
      assert.match(j.brief_path, /\.chain-runs\/.*\/epic-brief\.md$/);
      const copied = fs.readFileSync(path.join(REPO_ROOT, j.brief_path), 'utf-8');
      assert.match(copied, /# Shared epic brief/);
    } finally {
      fs.rmSync(tmp, { force: true });
    }
  });

  it('init with missing --brief path returns ERR_BRIEF_MISSING', () => {
    const r = run(`init --ids '["TRI-300"]' --brief /nonexistent/path/brief.md`);
    assert.equal(r.exit, 2);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_BRIEF_MISSING');
  });

  it('init with empty ids returns ERR_COUNT_ZERO', () => {
    const r = run(`init --ids '[]'`);
    assert.equal(r.exit, 2);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_COUNT_ZERO');
  });

  it('init with ids > 8 returns ERR_COUNT_EXCEEDED', () => {
    const ids = JSON.stringify(Array.from({ length: 9 }, (_, i) => `TRI-${i + 1}`));
    const r = run(`init --ids '${ids}'`);
    assert.equal(r.exit, 2);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_COUNT_EXCEEDED');
  });

  it('get for nonexistent run returns ERR_RUN_NOT_FOUND', () => {
    const r = run('get --run-id 99999999T000000-NOPE-999');
    assert.equal(r.exit, 4);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_RUN_NOT_FOUND');
  });
});
