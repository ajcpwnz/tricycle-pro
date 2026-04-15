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
  assert.equal(r.exit, 0, `init failed: ${r.stderr}`);
  return JSON.parse(r.stdout).run_id;
}

function cleanup(runId) {
  const dir = path.join(CHAIN_RUNS_DIR, runId);
  if (fs.existsSync(dir)) fs.rmSync(dir, { recursive: true, force: true });
}

describe('chain-run.sh update-ticket', () => {
  const runs = [];
  after(() => runs.forEach(cleanup));

  it('happy path: not_started → in_progress → completed', () => {
    const id = initRun(['TRI-100', 'TRI-101']);
    runs.push(id);

    let r = run(`update-ticket --run-id ${id} --ticket TRI-100 --status in_progress --started-now`);
    assert.equal(r.exit, 0);
    let s = JSON.parse(r.stdout);
    assert.equal(s.tickets['TRI-100'].status, 'in_progress');
    assert.ok(s.tickets['TRI-100'].started_at);
    assert.equal(s.current_index, 0);

    r = run(`update-ticket --run-id ${id} --ticket TRI-100 --status completed --finished-now --branch TRI-100-x --pr https://ex/1 --lint pass --test pass --report specs/.chain-runs/${id}/TRI-100.report.md`);
    assert.equal(r.exit, 0);
    s = JSON.parse(r.stdout);
    assert.equal(s.tickets['TRI-100'].status, 'completed');
    assert.equal(s.tickets['TRI-100'].branch, 'TRI-100-x');
    assert.equal(s.tickets['TRI-100'].pr_url, 'https://ex/1');
    assert.equal(s.tickets['TRI-100'].lint_status, 'pass');
    assert.equal(s.tickets['TRI-100'].test_status, 'pass');
    assert.ok(s.tickets['TRI-100'].finished_at);
    assert.equal(s.current_index, 1, 'current_index should advance past completed tickets');
  });

  it('--open-question appends entries', () => {
    const id = initRun(['TRI-200']);
    runs.push(id);
    const r = run(`update-ticket --run-id ${id} --ticket TRI-200 --status in_progress --open-question 'needs review' --open-question 'DB schema unclear'`);
    assert.equal(r.exit, 0);
    const s = JSON.parse(r.stdout);
    assert.deepEqual(s.tickets['TRI-200'].open_questions, ['needs review', 'DB schema unclear']);
  });

  it('pr_url without completed status returns ERR_PR_REQUIRES_COMPLETED', () => {
    const id = initRun(['TRI-300']);
    runs.push(id);
    const r = run(`update-ticket --run-id ${id} --ticket TRI-300 --status in_progress --pr https://ex/1`);
    assert.equal(r.exit, 2);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_PR_REQUIRES_COMPLETED');
  });

  it('ticket not in run returns ERR_TICKET_NOT_IN_RUN', () => {
    const id = initRun(['TRI-400']);
    runs.push(id);
    const r = run(`update-ticket --run-id ${id} --ticket TRI-999 --status completed`);
    assert.equal(r.exit, 5);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_TICKET_NOT_IN_RUN');
  });

  it('invalid status returns ERR_BAD_STATUS', () => {
    const id = initRun(['TRI-500']);
    runs.push(id);
    const r = run(`update-ticket --run-id ${id} --ticket TRI-500 --status wibble`);
    assert.equal(r.exit, 2);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_BAD_STATUS');
  });

  it('nonexistent run returns ERR_RUN_NOT_FOUND', () => {
    const r = run('update-ticket --run-id 99999999T000000-NOPE-999 --ticket TRI-1 --status completed');
    assert.equal(r.exit, 4);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_RUN_NOT_FOUND');
  });

  it('round-trip: update then get shows the change', () => {
    const id = initRun(['TRI-600', 'TRI-601']);
    runs.push(id);
    run(`update-ticket --run-id ${id} --ticket TRI-600 --status in_progress --started-now`);
    const getState = JSON.parse(run(`get --run-id ${id}`).stdout);
    assert.equal(getState.tickets['TRI-600'].status, 'in_progress');
  });
});
