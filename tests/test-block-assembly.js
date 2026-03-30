const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const REPO_ROOT = path.resolve(__dirname, '..');
const ASSEMBLE_SCRIPT = path.join(REPO_ROOT, 'core/scripts/bash/assemble-commands.sh');

function assemble(configContent, flags = '') {
  const tmpConfig = path.join(os.tmpdir(), `test-assemble-${Date.now()}.yml`);
  const tmpOutput = fs.mkdtempSync(path.join(os.tmpdir(), 'assemble-out-'));

  fs.writeFileSync(tmpConfig, configContent);

  try {
    const result = execSync(
      `bash "${ASSEMBLE_SCRIPT}" --config="${tmpConfig}" --output-dir="${tmpOutput}" ${flags}`,
      { cwd: REPO_ROOT, encoding: 'utf-8', timeout: 30000, stdio: ['pipe', 'pipe', 'pipe'] }
    );
    const files = {};
    for (const f of fs.readdirSync(tmpOutput)) {
      files[f] = fs.readFileSync(path.join(tmpOutput, f), 'utf-8');
    }
    return { files, stdout: result, exitCode: 0 };
  } catch (e) {
    return { files: {}, stdout: e.stdout || '', stderr: e.stderr || '', exitCode: e.status };
  } finally {
    fs.unlinkSync(tmpConfig);
    fs.rmSync(tmpOutput, { recursive: true, force: true });
  }
}

describe('block assembly', () => {
  it('default assembly produces all 5 command files', () => {
    const { files, exitCode } = assemble('project:\n  name: test\n');
    assert.equal(exitCode, 0);
    assert.ok(files['trc.specify.md'], 'trc.specify.md should exist');
    assert.ok(files['trc.plan.md'], 'trc.plan.md should exist');
    assert.ok(files['trc.tasks.md'], 'trc.tasks.md should exist');
    assert.ok(files['trc.implement.md'], 'trc.implement.md should exist');
    assert.ok(files['trc.headless.md'], 'trc.headless.md should exist');
  });

  it('assembled commands have YAML frontmatter', () => {
    const { files } = assemble('project:\n  name: test\n');
    assert.ok(files['trc.specify.md'].startsWith('---\n'));
    assert.ok(files['trc.plan.md'].startsWith('---\n'));
  });

  it('assembled commands have User Input section', () => {
    const { files } = assemble('project:\n  name: test\n');
    assert.ok(files['trc.specify.md'].includes('## User Input'));
    assert.ok(files['trc.specify.md'].includes('$ARGUMENTS'));
  });

  it('3-step chain generates blocked stub for tasks', () => {
    const { files } = assemble('workflow:\n  chain: [specify, plan, implement]\n');
    assert.ok(files['trc.tasks.md'].includes('## Blocked'), 'tasks should be blocked');
    assert.ok(files['trc.tasks.md'].includes('not part of the configured workflow chain'));
  });

  it('3-step chain absorbs tasks blocks into plan', () => {
    const { files } = assemble('workflow:\n  chain: [specify, plan, implement]\n');
    // Plan should contain task generation content (absorbed from tasks)
    assert.ok(files['trc.plan.md'].includes('Absorbed from tasks'), 'plan should have absorbed tasks blocks');
  });

  it('2-step chain blocks plan and tasks', () => {
    const { files } = assemble('workflow:\n  chain: [specify, implement]\n');
    assert.ok(files['trc.plan.md'].includes('## Blocked'));
    assert.ok(files['trc.tasks.md'].includes('## Blocked'));
  });

  it('2-step chain absorbs plan and tasks into specify', () => {
    const { files } = assemble('workflow:\n  chain: [specify, implement]\n');
    assert.ok(files['trc.specify.md'].includes('Absorbed from plan'));
    assert.ok(files['trc.specify.md'].includes('Absorbed from tasks'));
  });

  it('headless phase count matches chain length', () => {
    const { files: f4 } = assemble('workflow:\n  chain: [specify, plan, tasks, implement]\n');
    assert.ok(f4['trc.headless.md'].includes('Phase 1/4'));
    assert.ok(f4['trc.headless.md'].includes('Phase 4/4'));

    const { files: f2 } = assemble('workflow:\n  chain: [specify, implement]\n');
    assert.ok(f2['trc.headless.md'].includes('Phase 1/2'));
    assert.ok(f2['trc.headless.md'].includes('Phase 2/2'));
  });

  it('block ordering is correct', () => {
    const { files } = assemble('project:\n  name: test\n');
    const specify = files['trc.specify.md'];
    // feature-setup (10) should come before spec-writer (40)
    const setupIdx = specify.indexOf('feature branch');
    const writerIdx = specify.indexOf('execution flow') !== -1
      ? specify.indexOf('execution flow')
      : specify.indexOf('Extract key concepts');
    if (setupIdx !== -1 && writerIdx !== -1) {
      assert.ok(setupIdx < writerIdx, 'feature-setup should come before spec-writer');
    }
  });

  it('invalid chain produces error', () => {
    const { exitCode } = assemble('workflow:\n  chain: [implement, specify]\n');
    assert.notEqual(exitCode, 0);
  });

  it('disable removes block from output', () => {
    const { files } = assemble(
      'workflow:\n  chain: [specify, plan, tasks, implement]\n  blocks:\n    plan:\n      disable:\n        - design-contracts\n'
    );
    // Plan should NOT contain data-model/contracts content
    assert.ok(!files['trc.plan.md'].includes('design-contracts'));
  });

  it('enable adds optional block to output', () => {
    const { files } = assemble(
      'workflow:\n  blocks:\n    implement:\n      enable:\n        - test-local-stack\n'
    );
    assert.ok(files['trc.implement.md'].includes('Local Stack Testing'));
  });

  it('skills config injects skill invocations into assembled command', () => {
    const { files } = assemble(
      'workflow:\n  blocks:\n    implement:\n      skills:\n        - code-reviewer\n        - debugging\n'
    );
    const impl = files['trc.implement.md'];
    assert.ok(impl.includes('Skill Invocations'), 'should have Skill Invocations section');
    assert.ok(impl.includes('code-reviewer'), 'should reference code-reviewer skill');
    assert.ok(impl.includes('debugging'), 'should reference debugging skill');
    assert.ok(impl.includes('.claude/skills/code-reviewer/SKILL.md'), 'should have existence check');
  });

  it('no skills section when none configured', () => {
    const { files } = assemble('project:\n  name: test\n');
    assert.ok(!files['trc.implement.md'].includes('Skill Invocations'), 'should not have Skill Invocations section');
  });

  it('qa.enabled: true includes qa-testing block in implement', () => {
    const { files } = assemble('qa:\n  enabled: true\n');
    const impl = files['trc.implement.md'];
    assert.ok(impl.includes('QA Testing Gate'), 'should include QA Testing Gate section');
    assert.ok(impl.includes('qa/ai-agent-instructions.md'), 'should reference instructions file');
    assert.ok(impl.includes('HALT'), 'should include HALT directive');
  });

  it('qa.enabled: false does not include qa-testing block', () => {
    const { files } = assemble('qa:\n  enabled: false\n');
    assert.ok(!files['trc.implement.md'].includes('QA Testing Gate'), 'should not include QA Testing Gate');
  });

  it('qa section absent does not include qa-testing block', () => {
    const { files } = assemble('project:\n  name: test\n');
    assert.ok(!files['trc.implement.md'].includes('QA Testing Gate'), 'should not include QA Testing Gate');
  });

  it('manual enable works without qa.enabled', () => {
    const { files } = assemble(
      'workflow:\n  blocks:\n    implement:\n      enable:\n        - qa-testing\n'
    );
    assert.ok(files['trc.implement.md'].includes('QA Testing Gate'), 'should include QA Testing Gate via manual enable');
  });

  it('qa-testing block order is between task-execution and push-deploy', () => {
    const { files } = assemble('qa:\n  enabled: true\n');
    const impl = files['trc.implement.md'];
    const taskExecIdx = impl.indexOf('Test/Lint Gate');
    const qaIdx = impl.indexOf('QA Testing Gate');
    const pushIdx = impl.indexOf('Push, PR & Deploy');
    assert.ok(taskExecIdx < qaIdx, 'QA block should come after task-execution');
    assert.ok(qaIdx < pushIdx, 'QA block should come before push-deploy');
  });
});
