'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');

const REPO_ROOT = path.resolve(__dirname, '..');
const CACHE_HELPER = path.join(REPO_ROOT, 'core/scripts/bash/review-cache.sh');
const NORMALIZE = require(path.join(REPO_ROOT, 'core/scripts/node/normalize-pr-ref.js'));

function runCache(...args) {
  return execFileSync('bash', [CACHE_HELPER, ...args], {
    encoding: 'utf8',
    cwd: REPO_ROOT,
  }).trim();
}

// ─── PR reference normalization (US1) ────────────────────────────────────────

test('normalizePrRef accepts bare number', () => {
  const r = NORMALIZE.normalizePrRef('42');
  assert.equal(r.ok, true);
  assert.equal(r.number, 42);
});

test('normalizePrRef accepts hash-prefixed number', () => {
  const r = NORMALIZE.normalizePrRef('#42');
  assert.equal(r.ok, true);
  assert.equal(r.number, 42);
});

test('normalizePrRef accepts full GitHub PR URL', () => {
  const r = NORMALIZE.normalizePrRef('https://github.com/alex/tricycle-pro/pull/42');
  assert.equal(r.ok, true);
  assert.equal(r.number, 42);
});

test('normalizePrRef accepts GitHub URL with trailing segments', () => {
  const r = NORMALIZE.normalizePrRef('https://github.com/o/r/pull/99/files');
  assert.equal(r.ok, true);
  assert.equal(r.number, 99);
});

test('normalizePrRef rejects non-numeric input', () => {
  const r = NORMALIZE.normalizePrRef('abc');
  assert.equal(r.ok, false);
  assert.match(r.error, /expected PR number/);
});

test('normalizePrRef rejects empty string', () => {
  const r = NORMALIZE.normalizePrRef('');
  assert.equal(r.ok, false);
});

test('normalizePrRef rejects zero', () => {
  const r = NORMALIZE.normalizePrRef('0');
  assert.equal(r.ok, false);
});

test('normalizePrRef rejects negative number (via parse error)', () => {
  const r = NORMALIZE.normalizePrRef('-5');
  assert.equal(r.ok, false);
});

test('normalizePrRef rejects non-string input', () => {
  const r = NORMALIZE.normalizePrRef(42);
  assert.equal(r.ok, false);
});

test('normalizePrRef strips whitespace', () => {
  const r = NORMALIZE.normalizePrRef('  #42  ');
  assert.equal(r.ok, true);
  assert.equal(r.number, 42);
});

// ─── Cache path helper (US4) ─────────────────────────────────────────────────

test('cache path is deterministic hex for the same URL', () => {
  const p1 = runCache('path', 'https://example.com/rules.md');
  const p2 = runCache('path', 'https://example.com/rules.md');
  assert.equal(p1, p2);
  assert.match(p1, /\/\.trc\/cache\/review-sources\/[0-9a-f]+\.md$/);
});

test('cache path differs for different URLs', () => {
  const p1 = runCache('path', 'https://example.com/a.md');
  const p2 = runCache('path', 'https://example.com/b.md');
  assert.notEqual(p1, p2);
});

test('cache-dir prints the cache directory path', () => {
  const dir = runCache('cache-dir');
  assert.match(dir, /\/\.trc\/cache\/review-sources$/);
});

test('ensure-dir creates the cache directory and is idempotent', () => {
  const dir = runCache('ensure-dir');
  assert.ok(fs.existsSync(dir), 'cache dir should exist after ensure-dir');
  // Second call must still succeed.
  const dir2 = runCache('ensure-dir');
  assert.equal(dir, dir2);
  assert.ok(fs.existsSync(dir2));
});

test('cache path is under .trc/cache/review-sources', () => {
  const p = runCache('path', 'https://raw.githubusercontent.com/o/r/main/STYLE.md');
  const dir = runCache('cache-dir');
  assert.ok(
    p.startsWith(dir + '/'),
    `expected ${p} to be under ${dir}`
  );
});

test('review-cache.sh with unknown command exits non-zero', () => {
  assert.throws(() => runCache('nonsense'));
});

test('review-cache.sh path without URL exits non-zero', () => {
  assert.throws(() => runCache('path'));
});
