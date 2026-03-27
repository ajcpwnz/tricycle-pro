const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const REPO_ROOT = path.resolve(__dirname, '..');
const YAML_PARSER = path.join(REPO_ROOT, 'bin/lib/yaml_parser.sh');
const HELPERS = path.join(REPO_ROOT, 'bin/lib/helpers.sh');

function runBash(script) {
  return execSync(`bash -c 'source "${YAML_PARSER}" && source "${HELPERS}" && ${script}'`, {
    cwd: REPO_ROOT,
    encoding: 'utf-8',
    timeout: 10000,
  }).trim();
}

describe('skills config parsing', () => {
  it('parses skills.disable list', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-skills-disable.yml');
    fs.writeFileSync(tmpFile, [
      'project:',
      '  name: "test"',
      'skills:',
      '  disable:',
      '    - tdd',
      '    - document-writer',
    ].join('\n'));

    const result = runBash(`CONFIG_DATA=$(parse_yaml "${tmpFile}") && cfg_count skills.disable`);
    assert.equal(result, '2');

    const first = runBash(`CONFIG_DATA=$(parse_yaml "${tmpFile}") && cfg_get skills.disable.0`);
    assert.equal(first, 'tdd');

    const second = runBash(`CONFIG_DATA=$(parse_yaml "${tmpFile}") && cfg_get skills.disable.1`);
    assert.equal(second, 'document-writer');

    fs.unlinkSync(tmpFile);
  });

  it('parses skills.install list with source fields', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-skills-install.yml');
    fs.writeFileSync(tmpFile, [
      'project:',
      '  name: "test"',
      'skills:',
      '  install:',
      '    - source: "github:anthropics/skills/code-reviewer"',
      '    - source: "local:.trc/skills/my-custom"',
    ].join('\n'));

    const count = runBash(`CONFIG_DATA=$(parse_yaml "${tmpFile}") && cfg_count skills.install`);
    assert.equal(count, '2');

    const first = runBash(`CONFIG_DATA=$(parse_yaml "${tmpFile}") && cfg_get skills.install.0.source`);
    assert.equal(first, 'github:anthropics/skills/code-reviewer');

    const second = runBash(`CONFIG_DATA=$(parse_yaml "${tmpFile}") && cfg_get skills.install.1.source`);
    assert.equal(second, 'local:.trc/skills/my-custom');

    fs.unlinkSync(tmpFile);
  });

  it('returns 0 count when skills section is absent', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-skills-absent.yml');
    fs.writeFileSync(tmpFile, [
      'project:',
      '  name: "test"',
    ].join('\n'));

    const disableCount = runBash(`CONFIG_DATA=$(parse_yaml "${tmpFile}") && cfg_count skills.disable`);
    assert.equal(disableCount, '0');

    const installCount = runBash(`CONFIG_DATA=$(parse_yaml "${tmpFile}") && cfg_count skills.install`);
    assert.equal(installCount, '0');

    fs.unlinkSync(tmpFile);
  });

  it('cfg_has detects skills section presence', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-skills-has.yml');
    fs.writeFileSync(tmpFile, [
      'project:',
      '  name: "test"',
      'skills:',
      '  disable:',
      '    - tdd',
    ].join('\n'));

    const result = runBash(`CONFIG_DATA=$(parse_yaml "${tmpFile}") && cfg_has skills.disable && echo yes || echo no`);
    assert.equal(result, 'yes');

    const absent = runBash(`CONFIG_DATA=$(parse_yaml "${tmpFile}") && cfg_has skills.install && echo yes || echo no`);
    assert.equal(absent, 'no');

    fs.unlinkSync(tmpFile);
  });
});

describe('skill_checksum', () => {
  it('computes consistent checksum for skill directory', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'test-skill-'));
    fs.writeFileSync(path.join(tmpDir, 'SKILL.md'), '---\nname: test\n---\n# Test');
    fs.writeFileSync(path.join(tmpDir, 'README.md'), '# Test Skill');

    const cs1 = runBash(`detect_sha256 && skill_checksum "${tmpDir}"`);
    const cs2 = runBash(`detect_sha256 && skill_checksum "${tmpDir}"`);
    assert.equal(cs1, cs2);
    assert.equal(cs1.length, 16);

    fs.rmSync(tmpDir, { recursive: true });
  });

  it('excludes SOURCE file from checksum', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'test-skill-'));
    fs.writeFileSync(path.join(tmpDir, 'SKILL.md'), '---\nname: test\n---\n# Test');

    const csBefore = runBash(`detect_sha256 && skill_checksum "${tmpDir}"`);
    fs.writeFileSync(path.join(tmpDir, 'SOURCE'), 'origin: test\nchecksum: abc');
    const csAfter = runBash(`detect_sha256 && skill_checksum "${tmpDir}"`);

    assert.equal(csBefore, csAfter);

    fs.rmSync(tmpDir, { recursive: true });
  });
});

describe('generate_source_file', () => {
  it('creates SOURCE with expected fields', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'test-skill-'));
    fs.writeFileSync(path.join(tmpDir, 'SKILL.md'), '---\nname: test\n---\n# Test');

    runBash(`detect_sha256 && generate_source_file "${tmpDir}" "vendored:core/skills/test" "abc123"`);

    const source = fs.readFileSync(path.join(tmpDir, 'SOURCE'), 'utf-8');
    assert.ok(source.includes('origin: vendored:core/skills/test'));
    assert.ok(source.includes('commit: abc123'));
    assert.ok(source.includes('installed:'));
    assert.ok(source.includes('checksum:'));

    fs.rmSync(tmpDir, { recursive: true });
  });
});
