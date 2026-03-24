const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const REPO_ROOT = path.resolve(__dirname, '..');
const COMMON_SH = path.join(REPO_ROOT, 'core/scripts/bash/common.sh');

function runBash(script) {
  return execSync(`bash -c 'source "${COMMON_SH}" && ${script}'`, {
    cwd: REPO_ROOT,
    encoding: 'utf-8',
    timeout: 10000,
  }).trim();
}

function runBashExit(script) {
  try {
    execSync(`bash -c 'source "${COMMON_SH}" && ${script}'`, {
      cwd: REPO_ROOT,
      encoding: 'utf-8',
      timeout: 10000,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    return 0;
  } catch (e) {
    return e.status;
  }
}

describe('validate_chain', () => {
  it('accepts full chain', () => {
    const exit = runBashExit('validate_chain "specify plan tasks implement"');
    assert.equal(exit, 0);
  });

  it('accepts 3-step chain', () => {
    const exit = runBashExit('validate_chain "specify plan implement"');
    assert.equal(exit, 0);
  });

  it('accepts 2-step chain', () => {
    const exit = runBashExit('validate_chain "specify implement"');
    assert.equal(exit, 0);
  });

  it('rejects chain not starting with specify', () => {
    const exit = runBashExit('validate_chain "plan tasks implement"');
    assert.notEqual(exit, 0);
  });

  it('rejects chain not ending with implement', () => {
    const exit = runBashExit('validate_chain "specify plan tasks"');
    assert.notEqual(exit, 0);
  });

  it('rejects wrong order', () => {
    const exit = runBashExit('validate_chain "specify tasks plan implement"');
    assert.notEqual(exit, 0);
  });

  it('rejects unknown steps', () => {
    const exit = runBashExit('validate_chain "specify review implement"');
    assert.notEqual(exit, 0);
  });

  it('rejects single step', () => {
    const exit = runBashExit('validate_chain "implement"');
    assert.notEqual(exit, 0);
  });
});

describe('parse_chain_config', () => {
  it('returns default chain when no workflow section', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-no-workflow.yml');
    fs.writeFileSync(tmpFile, 'project:\n  name: test\n');
    const result = runBash(`parse_chain_config "${tmpFile}"`);
    assert.equal(result, 'specify plan tasks implement');
    fs.unlinkSync(tmpFile);
  });

  it('parses inline chain notation', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-inline.yml');
    fs.writeFileSync(tmpFile, 'workflow:\n  chain: [specify, plan, implement]\n');
    const result = runBash(`parse_chain_config "${tmpFile}"`);
    assert.equal(result, 'specify plan implement');
    fs.unlinkSync(tmpFile);
  });

  it('parses YAML list chain notation', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-list.yml');
    fs.writeFileSync(tmpFile, 'workflow:\n  chain:\n    - specify\n    - implement\n');
    const result = runBash(`parse_chain_config "${tmpFile}"`);
    assert.equal(result, 'specify implement');
    fs.unlinkSync(tmpFile);
  });

  it('returns default when file does not exist', () => {
    const result = runBash('parse_chain_config "/nonexistent/file.yml"');
    assert.equal(result, 'specify plan tasks implement');
  });
});
