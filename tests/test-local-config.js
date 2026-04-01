const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const REPO_ROOT = path.resolve(__dirname, '..');
const HELPERS_SH = path.join(REPO_ROOT, 'bin/lib/helpers.sh');
const YAML_PARSER_SH = path.join(REPO_ROOT, 'bin/lib/yaml_parser.sh');

function runBash(script) {
  return execSync(`bash -c 'source "${YAML_PARSER_SH}" && source "${HELPERS_SH}" && ${script}'`, {
    cwd: REPO_ROOT,
    encoding: 'utf-8',
    timeout: 10000,
  }).trim();
}

function runBashWithStderr(script) {
  try {
    const stdout = execSync(`bash -c 'source "${YAML_PARSER_SH}" && source "${HELPERS_SH}" && ${script}'`, {
      cwd: REPO_ROOT,
      encoding: 'utf-8',
      timeout: 10000,
    }).trim();
    return { stdout, stderr: '' };
  } catch (e) {
    return { stdout: (e.stdout || '').trim(), stderr: (e.stderr || '').trim() };
  }
}

function buildYaml(obj, indent = 0) {
  let yaml = '';
  const pad = '  '.repeat(indent);
  for (const [key, val] of Object.entries(obj)) {
    if (typeof val === 'object' && val !== null && !Array.isArray(val)) {
      yaml += `${pad}${key}:\n${buildYaml(val, indent + 1)}`;
    } else if (Array.isArray(val)) {
      yaml += `${pad}${key}:\n`;
      for (const item of val) {
        if (typeof item === 'object' && item !== null) {
          yaml += `${pad}  -\n${buildYaml(item, indent + 2)}`;
        } else {
          yaml += `${pad}  - ${item}\n`;
        }
      }
    } else {
      yaml += `${pad}${key}: ${val}\n`;
    }
  }
  return yaml;
}

describe('merge_config_data', () => {
  it('override scalar wins over base scalar', () => {
    const result = runBash(`merge_config_data "push.require_approval=true" "push.require_approval=false"`);
    assert.ok(result.includes('push.require_approval=false'));
    assert.ok(!result.includes('push.require_approval=true'));
  });

  it('preserves base keys not in override', () => {
    const base = 'project.name=myapp\npush.require_approval=true';
    const override = 'push.require_approval=false';
    const result = runBash(`merge_config_data "${base}" "${override}"`);
    assert.ok(result.includes('project.name=myapp'));
    assert.ok(result.includes('push.require_approval=false'));
  });

  it('adds new keys from override', () => {
    const result = runBash(`merge_config_data "project.name=myapp" "qa.enabled=true"`);
    assert.ok(result.includes('project.name=myapp'));
    assert.ok(result.includes('qa.enabled=true'));
  });

  it('replaces arrays entirely from override', () => {
    const base = 'workflow.blocks.specify.enable.0=worktree-setup\nworkflow.blocks.specify.enable.1=checklist';
    const override = 'workflow.blocks.specify.enable.0=qa-testing';
    const result = runBash(`merge_config_data "${base}" "${override}"`);
    assert.ok(result.includes('workflow.blocks.specify.enable.0=qa-testing'));
    assert.ok(!result.includes('worktree-setup'));
    assert.ok(!result.includes('checklist'));
  });

  it('returns base when override is empty', () => {
    const result = runBash('merge_config_data "project.name=myapp" ""');
    assert.equal(result, 'project.name=myapp');
  });
});

describe('validate_override', () => {
  it('passes valid overridable keys', () => {
    const result = runBash('validate_override "push.require_approval=false"');
    assert.ok(result.includes('push.require_approval=false'));
  });

  it('filters out non-overridable keys', () => {
    const result = runBash('validate_override "project.name=wrong"');
    assert.equal(result, '');
  });

  it('warns on non-overridable keys', () => {
    // Use subshell to capture stderr
    const result = execSync(`bash -c 'source "${YAML_PARSER_SH}" && source "${HELPERS_SH}" && validate_override "project.name=wrong" 2>&1 >/dev/null'`, {
      cwd: REPO_ROOT,
      encoding: 'utf-8',
      timeout: 10000,
    }).trim();
    assert.ok(result.includes('cannot be overridden locally'));
  });

  it('passes mixed keys and filters correctly', () => {
    const data = 'push.require_approval=false\nproject.name=wrong\nqa.enabled=true';
    const result = runBash(`validate_override "${data}"`);
    assert.ok(result.includes('push.require_approval=false'));
    assert.ok(result.includes('qa.enabled=true'));
    assert.ok(!result.includes('project.name'));
  });

  it('returns empty for empty input', () => {
    const result = runBash('validate_override ""');
    assert.equal(result, '');
  });

  it('passes workflow.blocks keys', () => {
    const result = runBash('validate_override "workflow.blocks.specify.enable.0=qa-testing"');
    assert.ok(result.includes('workflow.blocks.specify.enable.0=qa-testing'));
  });

  it('passes stealth keys', () => {
    const result = runBash('validate_override "stealth.enabled=true"');
    assert.ok(result.includes('stealth.enabled=true'));
  });

  it('passes worktree keys', () => {
    const result = runBash('validate_override "worktree.enabled=true"');
    assert.ok(result.includes('worktree.enabled=true'));
  });
});

describe('load_config with override', () => {
  it('loads merged config when override exists', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'trc-test-'));
    const baseConfig = buildYaml({
      project: { name: 'test-project', type: 'single-app' },
      push: { require_approval: 'true' },
    });
    const overrideConfig = buildYaml({
      push: { require_approval: 'false' },
    });
    fs.writeFileSync(path.join(tmpDir, 'tricycle.config.yml'), baseConfig);
    fs.writeFileSync(path.join(tmpDir, 'tricycle.config.local.yml'), overrideConfig);

    const result = execSync(`bash -c 'source "${YAML_PARSER_SH}" && source "${HELPERS_SH}" && CWD="${tmpDir}" && load_config && cfg_get push.require_approval'`, {
      cwd: REPO_ROOT,
      encoding: 'utf-8',
      timeout: 10000,
    }).trim();
    assert.equal(result, 'false');

    fs.rmSync(tmpDir, { recursive: true });
  });

  it('uses base config when no override exists', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'trc-test-'));
    const baseConfig = buildYaml({
      project: { name: 'test-project' },
      push: { require_approval: 'true' },
    });
    fs.writeFileSync(path.join(tmpDir, 'tricycle.config.yml'), baseConfig);

    const result = execSync(`bash -c 'source "${YAML_PARSER_SH}" && source "${HELPERS_SH}" && CWD="${tmpDir}" && load_config && cfg_get push.require_approval'`, {
      cwd: REPO_ROOT,
      encoding: 'utf-8',
      timeout: 10000,
    }).trim();
    assert.equal(result, 'true');

    fs.rmSync(tmpDir, { recursive: true });
  });

  it('falls back to base on invalid override YAML', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'trc-test-'));
    const baseConfig = buildYaml({
      project: { name: 'test-project' },
      push: { require_approval: 'true' },
    });
    fs.writeFileSync(path.join(tmpDir, 'tricycle.config.yml'), baseConfig);
    fs.writeFileSync(path.join(tmpDir, 'tricycle.config.local.yml'), '{{invalid yaml:::');

    const result = execSync(`bash -c 'source "${YAML_PARSER_SH}" && source "${HELPERS_SH}" && CWD="${tmpDir}" && load_config && cfg_get push.require_approval'`, {
      cwd: REPO_ROOT,
      encoding: 'utf-8',
      timeout: 10000,
    }).trim();
    assert.equal(result, 'true');

    fs.rmSync(tmpDir, { recursive: true });
  });

  it('ignores non-overridable keys in override', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'trc-test-'));
    const baseConfig = buildYaml({
      project: { name: 'test-project' },
      push: { require_approval: 'true' },
    });
    const overrideConfig = buildYaml({
      project: { name: 'hacked' },
      push: { require_approval: 'false' },
    });
    fs.writeFileSync(path.join(tmpDir, 'tricycle.config.yml'), baseConfig);
    fs.writeFileSync(path.join(tmpDir, 'tricycle.config.local.yml'), overrideConfig);

    const result = execSync(`bash -c 'source "${YAML_PARSER_SH}" && source "${HELPERS_SH}" && CWD="${tmpDir}" && load_config 2>/dev/null && echo "name=$(cfg_get project.name) approval=$(cfg_get push.require_approval)"'`, {
      cwd: REPO_ROOT,
      encoding: 'utf-8',
      timeout: 10000,
    }).trim();
    assert.ok(result.includes('name=test-project'));
    assert.ok(result.includes('approval=false'));

    fs.rmSync(tmpDir, { recursive: true });
  });

  it('handles empty override file gracefully', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'trc-test-'));
    const baseConfig = buildYaml({
      project: { name: 'test-project' },
      push: { require_approval: 'true' },
    });
    fs.writeFileSync(path.join(tmpDir, 'tricycle.config.yml'), baseConfig);
    fs.writeFileSync(path.join(tmpDir, 'tricycle.config.local.yml'), '');

    const result = execSync(`bash -c 'source "${YAML_PARSER_SH}" && source "${HELPERS_SH}" && CWD="${tmpDir}" && load_config && cfg_get push.require_approval'`, {
      cwd: REPO_ROOT,
      encoding: 'utf-8',
      timeout: 10000,
    }).trim();
    assert.equal(result, 'true');

    fs.rmSync(tmpDir, { recursive: true });
  });

  it('single key override works (minimal content)', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'trc-test-'));
    const baseConfig = buildYaml({
      project: { name: 'test-project' },
      worktree: { enabled: 'false' },
      push: { require_approval: 'true' },
    });
    fs.writeFileSync(path.join(tmpDir, 'tricycle.config.yml'), baseConfig);
    fs.writeFileSync(path.join(tmpDir, 'tricycle.config.local.yml'), 'worktree:\n  enabled: true\n');

    const result = execSync(`bash -c 'source "${YAML_PARSER_SH}" && source "${HELPERS_SH}" && CWD="${tmpDir}" && load_config && echo "wt=$(cfg_get worktree.enabled) approval=$(cfg_get push.require_approval) name=$(cfg_get project.name)"'`, {
      cwd: REPO_ROOT,
      encoding: 'utf-8',
      timeout: 10000,
    }).trim();
    assert.ok(result.includes('wt=true'));
    assert.ok(result.includes('approval=true'));
    assert.ok(result.includes('name=test-project'));

    fs.rmSync(tmpDir, { recursive: true });
  });
});

describe('VCS exclusion patterns', () => {
  it('normal-mode gitignore includes override file pattern', () => {
    const tricyclePath = path.join(REPO_ROOT, 'bin/tricycle');
    const content = fs.readFileSync(tricyclePath, 'utf-8');
    assert.ok(content.includes('tricycle.config.local.yml'));
  });

  it('normal-mode gitignore includes .trc/local/ pattern', () => {
    const tricyclePath = path.join(REPO_ROOT, 'bin/tricycle');
    const content = fs.readFileSync(tricyclePath, 'utf-8');
    assert.ok(content.includes('.trc/local/'));
  });

  it('stealth-mode block includes override file pattern', () => {
    const tricyclePath = path.join(REPO_ROOT, 'bin/tricycle');
    const content = fs.readFileSync(tricyclePath, 'utf-8');
    // Find the stealth heredoc content between STEALTH markers
    const stealthMatch = content.match(/stealth_block=\$\(cat << 'STEALTH'([\s\S]*?)STEALTH\n\)/);
    assert.ok(stealthMatch, 'stealth heredoc found');
    assert.ok(stealthMatch[1].includes('tricycle.config.local.yml'));
  });
});

describe('session-context hook override detection', () => {
  it('hook script contains override detection logic', () => {
    const hookPath = path.join(REPO_ROOT, 'core/hooks/session-context.sh');
    const content = fs.readFileSync(hookPath, 'utf-8');
    assert.ok(content.includes('tricycle.config.local.yml'));
    assert.ok(content.includes('.trc/local/commands'));
    assert.ok(content.includes('Local Config Overrides Active'));
  });
});
