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

describe('parse_block_overrides', () => {
  it('parses disable overrides', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-overrides-disable.yml');
    fs.writeFileSync(tmpFile, [
      'workflow:',
      '  blocks:',
      '    plan:',
      '      disable:',
      '        - design-contracts',
      '        - agent-context',
    ].join('\n'));

    const result = runBash(`parse_block_overrides "${tmpFile}" plan`);
    assert.ok(result.includes('disable=design-contracts'));
    assert.ok(result.includes('disable=agent-context'));
    fs.unlinkSync(tmpFile);
  });

  it('parses enable overrides', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-overrides-enable.yml');
    fs.writeFileSync(tmpFile, [
      'workflow:',
      '  blocks:',
      '    implement:',
      '      enable:',
      '        - test-local-stack',
    ].join('\n'));

    const result = runBash(`parse_block_overrides "${tmpFile}" implement`);
    assert.ok(result.includes('enable=test-local-stack'));
    fs.unlinkSync(tmpFile);
  });

  it('parses custom block paths', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-overrides-custom.yml');
    fs.writeFileSync(tmpFile, [
      'workflow:',
      '  blocks:',
      '    implement:',
      '      custom:',
      '        - .trc/blocks/custom/my-block.md',
    ].join('\n'));

    const result = runBash(`parse_block_overrides "${tmpFile}" implement`);
    assert.ok(result.includes('custom=.trc/blocks/custom/my-block.md'));
    fs.unlinkSync(tmpFile);
  });

  it('returns empty for missing config', () => {
    const result = runBash('parse_block_overrides "/nonexistent" plan');
    assert.equal(result, '');
  });

  it('returns empty for step with no overrides', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-overrides-none.yml');
    fs.writeFileSync(tmpFile, [
      'workflow:',
      '  blocks:',
      '    plan:',
      '      disable:',
      '        - design-contracts',
    ].join('\n'));

    const result = runBash(`parse_block_overrides "${tmpFile}" implement`);
    assert.equal(result, '');
    fs.unlinkSync(tmpFile);
  });
});

describe('parse_block_frontmatter', () => {
  it('parses block frontmatter fields', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-block-fm.md');
    fs.writeFileSync(tmpFile, [
      '---',
      'name: test-block',
      'step: implement',
      'description: A test block',
      'required: false',
      'default_enabled: true',
      'order: 25',
      '---',
      '',
      'Block content here',
    ].join('\n'));

    const result = runBash(`parse_block_frontmatter "${tmpFile}"`);
    assert.ok(result.includes('name=test-block'));
    assert.ok(result.includes('step=implement'));
    assert.ok(result.includes('required=false'));
    assert.ok(result.includes('default_enabled=true'));
    assert.ok(result.includes('order=25'));
    fs.unlinkSync(tmpFile);
  });

  it('get_block_field extracts a single field', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-block-field.md');
    fs.writeFileSync(tmpFile, [
      '---',
      'name: my-block',
      'step: plan',
      'order: 42',
      '---',
      '',
      'content',
    ].join('\n'));

    const result = runBash(`get_block_field "${tmpFile}" order`);
    assert.equal(result, '42');
    fs.unlinkSync(tmpFile);
  });
});

describe('read_block_content', () => {
  it('extracts content after frontmatter', () => {
    const tmpFile = path.join(os.tmpdir(), 'test-block-content.md');
    fs.writeFileSync(tmpFile, [
      '---',
      'name: test',
      '---',
      '',
      '## My Section',
      '',
      'Some content here.',
    ].join('\n'));

    const result = runBash(`read_block_content "${tmpFile}"`);
    assert.ok(result.includes('## My Section'));
    assert.ok(result.includes('Some content here.'));
    assert.ok(!result.includes('name: test'));
    fs.unlinkSync(tmpFile);
  });
});
