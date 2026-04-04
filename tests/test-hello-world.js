const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('child_process');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..');
const TRICYCLE = path.join(REPO_ROOT, 'bin/tricycle');

function runTricycle(args = '') {
  return execSync(`bash "${TRICYCLE}" ${args}`, {
    cwd: REPO_ROOT,
    encoding: 'utf-8',
    timeout: 10000,
  });
}

describe('hello-world command', () => {
  it('prints "Hello, world!" to stdout', () => {
    const output = runTricycle('hello-world');
    assert.equal(output.trim(), 'Hello, world!');
  });

  it('exits with code 0', () => {
    // execSync throws on non-zero exit, so reaching here means exit 0
    runTricycle('hello-world');
  });

  it('ignores extra arguments', () => {
    const output = runTricycle('hello-world foo bar baz');
    assert.equal(output.trim(), 'Hello, world!');
  });
});
