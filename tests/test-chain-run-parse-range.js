const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('child_process');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..');
const CHAIN = path.join(REPO_ROOT, 'core/scripts/bash/chain-run.sh');

function run(args) {
  try {
    const out = execSync(`bash "${CHAIN}" parse-range ${args}`, {
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

describe('chain-run.sh parse-range', () => {
  it('happy path: contiguous range', () => {
    const r = run('"TRI-100..TRI-102"');
    assert.equal(r.exit, 0);
    const j = JSON.parse(r.stdout);
    assert.deepEqual(j.ids, ['TRI-100', 'TRI-101', 'TRI-102']);
    assert.equal(j.count, 3);
  });

  it('happy path: mixed-prefix comma list', () => {
    const r = run('"TRI-100,POL-42,TRI-101"');
    assert.equal(r.exit, 0);
    const j = JSON.parse(r.stdout);
    assert.deepEqual(j.ids, ['TRI-100', 'POL-42', 'TRI-101']);
    assert.equal(j.count, 3);
  });

  it('happy path: single ticket', () => {
    const r = run('"TRI-42"');
    assert.equal(r.exit, 0);
    const j = JSON.parse(r.stdout);
    assert.deepEqual(j.ids, ['TRI-42']);
  });

  it('dedup: repeated tokens collapse', () => {
    const r = run('"TRI-100,TRI-100,TRI-101"');
    assert.equal(r.exit, 0);
    const j = JSON.parse(r.stdout);
    assert.deepEqual(j.ids, ['TRI-100', 'TRI-101']);
    assert.equal(j.count, 2);
  });

  it('error: count > 8 in range', () => {
    const r = run('"TRI-1..TRI-9"');
    assert.equal(r.exit, 2);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_COUNT_EXCEEDED');
  });

  it('error: count > 8 in list', () => {
    const r = run('"TRI-1,TRI-2,TRI-3,TRI-4,TRI-5,TRI-6,TRI-7,TRI-8,TRI-9"');
    assert.equal(r.exit, 2);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_COUNT_EXCEEDED');
  });

  it('error: mixed prefix in range form', () => {
    const r = run('"TRI-1..POL-5"');
    assert.equal(r.exit, 2);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_RANGE_MIXED_PREFIX');
  });

  it('error: descending range', () => {
    const r = run('"TRI-5..TRI-1"');
    assert.equal(r.exit, 2);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_RANGE_DESCENDING');
  });

  it('error: malformed token (lowercase)', () => {
    const r = run('"tri-100"');
    assert.equal(r.exit, 2);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_MALFORMED_TOKEN');
  });

  it('error: empty input', () => {
    const r = run('""');
    assert.equal(r.exit, 2);
    const e = JSON.parse(r.stderr);
    assert.equal(e.code, 'ERR_EMPTY_INPUT');
  });

  it('accepts the maximum of 8 tickets', () => {
    const r = run('"TRI-1..TRI-8"');
    assert.equal(r.exit, 0);
    const j = JSON.parse(r.stdout);
    assert.equal(j.count, 8);
  });
});
