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

  it('happy path: full TRI-30 transition not_started → in_progress → committed → pushed → merged → completed', () => {
    const id = initRun(['TRI-100', 'TRI-101']);
    runs.push(id);

    let r = run(`update-ticket --run-id ${id} --ticket TRI-100 --status in_progress --started-now`);
    assert.equal(r.exit, 0);
    let s = JSON.parse(r.stdout);
    assert.equal(s.tickets['TRI-100'].status, 'in_progress');
    assert.ok(s.tickets['TRI-100'].started_at);
    assert.equal(s.current_index, 0);

    r = run(`update-ticket --run-id ${id} --ticket TRI-100 --status committed --commit-sha abc123def --branch TRI-100-x --lint pass --test pass --report specs/.chain-runs/${id}/TRI-100.report.md`);
    assert.equal(r.exit, 0, `committed step failed: ${r.stderr}`);
    s = JSON.parse(r.stdout);
    assert.equal(s.tickets['TRI-100'].status, 'committed');
    assert.equal(s.tickets['TRI-100'].commit_sha, 'abc123def');
    assert.equal(s.tickets['TRI-100'].branch, 'TRI-100-x');
    assert.equal(s.tickets['TRI-100'].lint_status, 'pass');
    assert.equal(s.tickets['TRI-100'].test_status, 'pass');
    assert.equal(s.current_index, 1, 'current_index should advance past committed tickets');

    r = run(`update-ticket --run-id ${id} --ticket TRI-100 --status pushed --pr https://ex/1`);
    assert.equal(r.exit, 0, `pushed step failed: ${r.stderr}`);
    s = JSON.parse(r.stdout);
    assert.equal(s.tickets['TRI-100'].status, 'pushed');
    assert.equal(s.tickets['TRI-100'].pr_url, 'https://ex/1');
    assert.equal(s.tickets['TRI-100'].commit_sha, 'abc123def', 'commit_sha persists across transitions');

    r = run(`update-ticket --run-id ${id} --ticket TRI-100 --status merged`);
    assert.equal(r.exit, 0, `merged step failed: ${r.stderr}`);
    assert.equal(JSON.parse(r.stdout).tickets['TRI-100'].status, 'merged');

    r = run(`update-ticket --run-id ${id} --ticket TRI-100 --status completed --finished-now`);
    assert.equal(r.exit, 0, `completed step failed: ${r.stderr}`);
    s = JSON.parse(r.stdout);
    assert.equal(s.tickets['TRI-100'].status, 'completed');
    assert.ok(s.tickets['TRI-100'].finished_at);
    assert.equal(s.tickets['TRI-100'].commit_sha, 'abc123def');
  });

  it('committed without --commit-sha returns ERR_COMMIT_SHA_REQUIRED', () => {
    const id = initRun(['TRI-150']);
    runs.push(id);
    run(`update-ticket --run-id ${id} --ticket TRI-150 --status in_progress`);
    const r = run(`update-ticket --run-id ${id} --ticket TRI-150 --status committed`);
    assert.equal(r.exit, 2);
    assert.equal(JSON.parse(r.stderr).code, 'ERR_COMMIT_SHA_REQUIRED');
  });

  it('commit_sha is immutable on second different value', () => {
    const id = initRun(['TRI-160']);
    runs.push(id);
    run(`update-ticket --run-id ${id} --ticket TRI-160 --status in_progress`);
    run(`update-ticket --run-id ${id} --ticket TRI-160 --status committed --commit-sha first`);
    const r = run(`update-ticket --run-id ${id} --ticket TRI-160 --status pushed --pr https://ex/1 --commit-sha different`);
    assert.equal(r.exit, 2);
    assert.equal(JSON.parse(r.stderr).code, 'ERR_COMMIT_SHA_IMMUTABLE');
  });

  it('backward transition (committed → in_progress) returns ERR_BAD_TRANSITION', () => {
    const id = initRun(['TRI-170']);
    runs.push(id);
    run(`update-ticket --run-id ${id} --ticket TRI-170 --status in_progress`);
    run(`update-ticket --run-id ${id} --ticket TRI-170 --status committed --commit-sha s`);
    const r = run(`update-ticket --run-id ${id} --ticket TRI-170 --status in_progress`);
    assert.equal(r.exit, 2);
    assert.equal(JSON.parse(r.stderr).code, 'ERR_BAD_TRANSITION');
  });

  it('skip-forward transition (not_started → merged) returns ERR_BAD_TRANSITION', () => {
    const id = initRun(['TRI-180']);
    runs.push(id);
    const r = run(`update-ticket --run-id ${id} --ticket TRI-180 --status merged`);
    assert.equal(r.exit, 2);
    assert.equal(JSON.parse(r.stderr).code, 'ERR_BAD_TRANSITION');
  });

  it('skip-forward (in_progress → pushed) returns ERR_BAD_TRANSITION', () => {
    const id = initRun(['TRI-185']);
    runs.push(id);
    run(`update-ticket --run-id ${id} --ticket TRI-185 --status in_progress`);
    const r = run(`update-ticket --run-id ${id} --ticket TRI-185 --status pushed --pr https://ex/1`);
    assert.equal(r.exit, 2);
    assert.equal(JSON.parse(r.stderr).code, 'ERR_BAD_TRANSITION');
  });

  it('failed is legal from any non-terminal state', () => {
    const id = initRun(['TRI-190', 'TRI-191', 'TRI-192']);
    runs.push(id);
    // From in_progress
    run(`update-ticket --run-id ${id} --ticket TRI-190 --status in_progress`);
    let r = run(`update-ticket --run-id ${id} --ticket TRI-190 --status failed`);
    assert.equal(r.exit, 0);
    // From committed
    run(`update-ticket --run-id ${id} --ticket TRI-191 --status in_progress`);
    run(`update-ticket --run-id ${id} --ticket TRI-191 --status committed --commit-sha s`);
    r = run(`update-ticket --run-id ${id} --ticket TRI-191 --status failed`);
    assert.equal(r.exit, 0);
  });

  it('skipped is legal only from not_started', () => {
    const id = initRun(['TRI-195']);
    runs.push(id);
    // Legal from not_started
    let r = run(`update-ticket --run-id ${id} --ticket TRI-195 --status skipped`);
    assert.equal(r.exit, 0);
    // Illegal from in_progress
    const id2 = initRun(['TRI-196']);
    runs.push(id2);
    run(`update-ticket --run-id ${id2} --ticket TRI-196 --status in_progress`);
    r = run(`update-ticket --run-id ${id2} --ticket TRI-196 --status skipped`);
    assert.equal(r.exit, 2);
    assert.equal(JSON.parse(r.stderr).code, 'ERR_BAD_TRANSITION');
  });

  it('--open-question appends entries', () => {
    const id = initRun(['TRI-200']);
    runs.push(id);
    const r = run(`update-ticket --run-id ${id} --ticket TRI-200 --status in_progress --open-question 'needs review' --open-question 'DB schema unclear'`);
    assert.equal(r.exit, 0);
    const s = JSON.parse(r.stdout);
    assert.deepEqual(s.tickets['TRI-200'].open_questions, ['needs review', 'DB schema unclear']);
  });

  it('pr_url at in_progress status returns ERR_PR_REQUIRES_PUSHED_OR_LATER', () => {
    const id = initRun(['TRI-300']);
    runs.push(id);
    const r = run(`update-ticket --run-id ${id} --ticket TRI-300 --status in_progress --pr https://ex/1`);
    assert.equal(r.exit, 2);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_PR_REQUIRES_PUSHED_OR_LATER');
  });

  it('pr_url is allowed at status=pushed (TRI-30 relaxation)', () => {
    const id = initRun(['TRI-310']);
    runs.push(id);
    run(`update-ticket --run-id ${id} --ticket TRI-310 --status in_progress`);
    run(`update-ticket --run-id ${id} --ticket TRI-310 --status committed --commit-sha sha`);
    const r = run(`update-ticket --run-id ${id} --ticket TRI-310 --status pushed --pr https://ex/1`);
    assert.equal(r.exit, 0);
    assert.equal(JSON.parse(r.stdout).tickets['TRI-310'].pr_url, 'https://ex/1');
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
