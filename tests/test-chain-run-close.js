const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const REPO_ROOT = path.resolve(__dirname, '..');
const CHAIN = path.join(REPO_ROOT, 'core/scripts/bash/chain-run.sh');
const CHAIN_RUNS_DIR = path.join(REPO_ROOT, 'specs/.chain-runs');

function run(args) {
  try {
    const out = execSync(`bash "${CHAIN}" ${args}`, {
      cwd: REPO_ROOT,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout: 10000,
    });
    return { exit: 0, stdout: out.trim(), stderr: '' };
  } catch (e) {
    return { exit: e.status, stdout: (e.stdout || '').toString().trim(), stderr: (e.stderr || '').toString().trim() };
  }
}

function initRun(ids) {
  const r = run(`init --ids '${JSON.stringify(ids)}'`);
  return JSON.parse(r.stdout).run_id;
}

function cleanup(runId) {
  const dir = path.join(CHAIN_RUNS_DIR, runId);
  if (fs.existsSync(dir)) fs.rmSync(dir, { recursive: true, force: true });
}

describe('chain-run.sh close', () => {
  const runs = [];
  after(() => runs.forEach(cleanup));

  it('close completed sets status=completed', () => {
    const id = initRun(['TRI-700']);
    runs.push(id);
    const r = run(`close --run-id ${id} --terminal-status completed`);
    assert.equal(r.exit, 0);
    const s = JSON.parse(r.stdout);
    assert.equal(s.status, 'completed');
    assert.equal(s.terminal_reason, null);
  });

  it('close failed sets status=failed and reason', () => {
    const id = initRun(['TRI-800']);
    runs.push(id);
    const r = run(`close --run-id ${id} --terminal-status failed --reason "tests failed"`);
    assert.equal(r.exit, 0);
    const s = JSON.parse(r.stdout);
    assert.equal(s.status, 'failed');
    assert.equal(s.terminal_reason, 'tests failed');
  });

  it('close aborted sets status=aborted', () => {
    const id = initRun(['TRI-900']);
    runs.push(id);
    const r = run(`close --run-id ${id} --terminal-status aborted --reason "user discarded"`);
    assert.equal(r.exit, 0);
    const s = JSON.parse(r.stdout);
    assert.equal(s.status, 'aborted');
  });

  it('close is idempotent on already-closed runs', () => {
    const id = initRun(['TRI-1000']);
    runs.push(id);
    run(`close --run-id ${id} --terminal-status completed`);
    const r = run(`close --run-id ${id} --terminal-status completed`);
    assert.equal(r.exit, 0, 'second close should succeed');
    const s = JSON.parse(r.stdout);
    assert.equal(s.status, 'completed');
  });

  it('close with invalid terminal-status returns ERR_BAD_STATUS', () => {
    const id = initRun(['TRI-1100']);
    runs.push(id);
    const r = run(`close --run-id ${id} --terminal-status wibble`);
    assert.equal(r.exit, 2);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_BAD_STATUS');
  });

  it('close nonexistent run returns ERR_RUN_NOT_FOUND', () => {
    const r = run('close --run-id 99999999T000000-NOPE-999 --terminal-status completed');
    assert.equal(r.exit, 4);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_RUN_NOT_FOUND');
  });

  it('close removes .progress files', () => {
    const id = initRun(['TRI-1200']);
    runs.push(id);
    const runDir = path.join(CHAIN_RUNS_DIR, id);
    fs.writeFileSync(path.join(runDir, 'TRI-1200.progress'), '{"phase":"plan"}\n');
    assert.ok(fs.existsSync(path.join(runDir, 'TRI-1200.progress')));
    run(`close --run-id ${id} --terminal-status completed`);
    assert.ok(!fs.existsSync(path.join(runDir, 'TRI-1200.progress')), 'progress file should be gone');
  });
});
