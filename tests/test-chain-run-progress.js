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
  return JSON.parse(run(`init --ids '${JSON.stringify(ids)}'`).stdout).run_id;
}

function cleanup(runId) {
  const dir = path.join(CHAIN_RUNS_DIR, runId);
  if (fs.existsSync(dir)) fs.rmSync(dir, { recursive: true, force: true });
}

describe('chain-run.sh progress', () => {
  const runs = [];
  after(() => runs.forEach(cleanup));

  it('returns phase=unknown when no progress file exists', () => {
    const id = initRun(['TRI-3100']);
    runs.push(id);
    const r = run(`progress --run-id ${id} --ticket TRI-3100`);
    assert.equal(r.exit, 0);
    const j = JSON.parse(r.stdout);
    assert.equal(j.phase, 'unknown');
    assert.equal(j.ticket_id, 'TRI-3100');
  });

  it('reads current progress file content (TRI-30: end-of-phase events)', () => {
    const id = initRun(['TRI-3200']);
    runs.push(id);
    const runDir = path.join(CHAIN_RUNS_DIR, id);
    const event = {
      phase: 'plan_complete',
      completed_at: '2026-04-15T12:00:00Z',
      ticket_id: 'TRI-3200',
    };
    fs.writeFileSync(path.join(runDir, 'TRI-3200.progress'), JSON.stringify(event) + '\n');

    const r = run(`progress --run-id ${id} --ticket TRI-3200`);
    assert.equal(r.exit, 0);
    const j = JSON.parse(r.stdout);
    assert.equal(j.phase, 'plan_complete');
    assert.equal(j.completed_at, '2026-04-15T12:00:00Z');
  });

  it('latest-write-wins (overwrite semantics)', () => {
    const id = initRun(['TRI-3300']);
    runs.push(id);
    const runDir = path.join(CHAIN_RUNS_DIR, id);
    const pf = path.join(runDir, 'TRI-3300.progress');
    fs.writeFileSync(pf, JSON.stringify({ phase: 'specify_complete', ticket_id: 'TRI-3300' }) + '\n');
    fs.writeFileSync(pf, JSON.stringify({ phase: 'implement_complete', ticket_id: 'TRI-3300' }) + '\n');
    const j = JSON.parse(run(`progress --run-id ${id} --ticket TRI-3300`).stdout);
    assert.equal(j.phase, 'implement_complete');
  });

  it('TRI-30 final committed event includes commit_sha', () => {
    const id = initRun(['TRI-3400']);
    runs.push(id);
    const runDir = path.join(CHAIN_RUNS_DIR, id);
    const event = {
      phase: 'committed',
      completed_at: '2026-04-15T12:00:00Z',
      ticket_id: 'TRI-3400',
      commit_sha: 'abc123def',
    };
    fs.writeFileSync(path.join(runDir, 'TRI-3400.progress'), JSON.stringify(event) + '\n');
    const r = run(`progress --run-id ${id} --ticket TRI-3400`);
    assert.equal(r.exit, 0);
    const j = JSON.parse(r.stdout);
    assert.equal(j.phase, 'committed');
    assert.equal(j.commit_sha, 'abc123def');
  });
});
