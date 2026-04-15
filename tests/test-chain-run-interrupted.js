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

describe('chain-run.sh list-interrupted', () => {
  const runs = [];
  after(() => runs.forEach(cleanup));

  it('returns the interrupted run with next_ticket_id', () => {
    const id = initRun(['TRI-2100', 'TRI-2101', 'TRI-2102']);
    runs.push(id);
    run(`update-ticket --run-id ${id} --ticket TRI-2100 --status completed --finished-now --lint pass --test pass`);

    const r = run('list-interrupted');
    assert.equal(r.exit, 0);
    const j = JSON.parse(r.stdout);
    const found = j.runs.find((x) => x.run_id === id);
    assert.ok(found, 'run should be listed');
    assert.equal(found.next_ticket_id, 'TRI-2101');
    assert.equal(found.current_index, 1);
  });

  it('excludes closed runs', () => {
    const id = initRun(['TRI-2200']);
    runs.push(id);
    run(`close --run-id ${id} --terminal-status completed`);

    const j = JSON.parse(run('list-interrupted').stdout);
    assert.ok(!j.runs.find((x) => x.run_id === id), 'closed run should not be listed');
  });

  it('excludes failed and aborted runs', () => {
    const idFail = initRun(['TRI-2300']);
    const idAbort = initRun(['TRI-2400']);
    runs.push(idFail, idAbort);
    run(`close --run-id ${idFail} --terminal-status failed --reason "test"`);
    run(`close --run-id ${idAbort} --terminal-status aborted --reason "test"`);

    const j = JSON.parse(run('list-interrupted').stdout);
    assert.ok(!j.runs.find((x) => x.run_id === idFail));
    assert.ok(!j.runs.find((x) => x.run_id === idAbort));
  });

  it('returns empty list when no runs exist (no error)', () => {
    // Don't create any runs; just verify baseline structure.
    const r = run('list-interrupted');
    assert.equal(r.exit, 0);
    const j = JSON.parse(r.stdout);
    assert.ok(Array.isArray(j.runs));
  });
});
