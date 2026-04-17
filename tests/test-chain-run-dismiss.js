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
    return {
      exit: e.status,
      stdout: (e.stdout || '').toString().trim(),
      stderr: (e.stderr || '').toString().trim(),
    };
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

describe('chain-run.sh dismiss', () => {
  const runs = [];
  after(() => runs.forEach(cleanup));

  it('dismiss hides an in-progress run from list-interrupted', () => {
    const id = initRun(['TRI-901']);
    runs.push(id);

    let r = run('list-interrupted');
    assert.equal(r.exit, 0);
    let parsed = JSON.parse(r.stdout);
    assert.ok(parsed.runs.some((x) => x.run_id === id), 'run should appear before dismiss');

    r = run(`dismiss --run-id ${id}`);
    assert.equal(r.exit, 0, `dismiss failed: ${r.stderr}`);
    const state = JSON.parse(r.stdout);
    assert.ok(state.dismissed_at, 'dismissed_at should be set');
    assert.equal(state.status, 'in_progress', 'dismiss must not close the run');

    r = run('list-interrupted');
    parsed = JSON.parse(r.stdout);
    assert.ok(
      !parsed.runs.some((x) => x.run_id === id),
      'dismissed run must be hidden from list-interrupted',
    );
  });

  it('dismiss is idempotent', () => {
    const id = initRun(['TRI-902']);
    runs.push(id);

    const r1 = run(`dismiss --run-id ${id}`);
    assert.equal(r1.exit, 0);
    const r2 = run(`dismiss --run-id ${id}`);
    assert.equal(r2.exit, 0, 're-dismissing should succeed');
  });

  it('dismiss on unknown run returns ERR_RUN_NOT_FOUND', () => {
    const r = run('dismiss --run-id 20990101T000000aaaa-NOPE-1');
    assert.notEqual(r.exit, 0);
    assert.match(r.stderr, /ERR_RUN_NOT_FOUND/);
  });
});

describe('chain-run.sh update-ticket hedging guard', () => {
  const runs = [];
  after(() => runs.forEach(cleanup));

  it('rejects status=committed when open_questions contains push-approval hedging', () => {
    const id = initRun(['TRI-903']);
    runs.push(id);

    let r = run(`update-ticket --run-id ${id} --ticket TRI-903 --status in_progress --started-now`);
    assert.equal(r.exit, 0);

    r = run(
      `update-ticket --run-id ${id} --ticket TRI-903 --status committed ` +
        `--commit-sha abc --branch TRI-903-x --lint pass --test pass ` +
        `--open-question "Push approval: may I push now?"`,
    );
    assert.notEqual(r.exit, 0, 'hedging on committed must be rejected');
    assert.match(r.stderr, /ERR_COMMITTED_HEDGING/);

    // State must remain in_progress — the bad transition did not land.
    r = run(`get --run-id ${id}`);
    const state = JSON.parse(r.stdout);
    assert.equal(state.tickets['TRI-903'].status, 'in_progress');
  });

  it('accepts status=committed with benign open_questions caveats', () => {
    const id = initRun(['TRI-904']);
    runs.push(id);

    let r = run(`update-ticket --run-id ${id} --ticket TRI-904 --status in_progress --started-now`);
    assert.equal(r.exit, 0);

    r = run(
      `update-ticket --run-id ${id} --ticket TRI-904 --status committed ` +
        `--commit-sha def --branch TRI-904-x --lint pass --test pass ` +
        `--open-question "Consider backfilling the legacy rows in a follow-up."`,
    );
    assert.equal(r.exit, 0, `benign caveat should be allowed: ${r.stderr}`);
    const state = JSON.parse(r.stdout);
    assert.equal(state.tickets['TRI-904'].status, 'committed');
    assert.deepEqual(state.tickets['TRI-904'].open_questions, [
      'Consider backfilling the legacy rows in a follow-up.',
    ]);
  });
});
