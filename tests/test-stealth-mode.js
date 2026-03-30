const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const REPO_ROOT = path.resolve(__dirname, '..');
const CLI = path.join(REPO_ROOT, 'bin/tricycle');

/**
 * Create a temp git repo with a tricycle config.
 * Returns { dir, configPath, excludePath, gitignorePath }
 */
function createTestRepo(configOverrides = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'stealth-test-'));
  execSync('git init -q', { cwd: dir });
  execSync('git commit --allow-empty -m "init" -q', { cwd: dir });

  const config = {
    'project.name': 'test-stealth',
    'project.type': 'single-app',
    'project.package_manager': 'npm',
    'project.base_branch': 'main',
    'stealth.enabled': 'false',
    'stealth.ignore_target': 'exclude',
    ...configOverrides,
  };

  // Build YAML from flat keys
  const yaml = buildYaml(config);
  const configPath = path.join(dir, 'tricycle.config.yml');
  fs.writeFileSync(configPath, yaml);

  const gitDir = execSync('git rev-parse --absolute-git-dir', { cwd: dir, encoding: 'utf-8' }).trim();
  const excludePath = path.join(gitDir, 'info', 'exclude');
  const gitignorePath = path.join(dir, '.gitignore');

  return { dir, configPath, excludePath, gitignorePath };
}

function buildYaml(flatConfig) {
  const lines = [];
  const sections = {};

  for (const [key, value] of Object.entries(flatConfig)) {
    const parts = key.split('.');
    if (parts.length === 1) {
      lines.push(`${parts[0]}: ${value}`);
    } else if (parts.length === 2) {
      if (!sections[parts[0]]) sections[parts[0]] = [];
      sections[parts[0]].push(`  ${parts[1]}: ${value}`);
    }
  }

  for (const [section, entries] of Object.entries(sections)) {
    lines.push(`${section}:`);
    lines.push(...entries);
  }

  return lines.join('\n') + '\n';
}

function runGenerateGitignore(dir) {
  execSync(`cd "${dir}" && "${CLI}" generate gitignore`, {
    encoding: 'utf-8',
    timeout: 10000,
    stdio: 'pipe',
  });
}

function readFileOrEmpty(filePath) {
  try {
    return fs.readFileSync(filePath, 'utf-8');
  } catch {
    return '';
  }
}

const STEALTH_MARKER_START = '# >>> tricycle stealth';
const STEALTH_MARKER_END = '# <<< tricycle stealth';
const STEALTH_PATHS = ['.claude/', '.trc/', 'specs/', 'tricycle.config.yml', '.tricycle.lock', '.mcp.json'];

function cleanup(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
}

describe('stealth mode', () => {
  it('stealth enable writes block to .git/info/exclude (default target)', () => {
    const { dir, excludePath } = createTestRepo({
      'stealth.enabled': 'true',
    });

    runGenerateGitignore(dir);

    const content = readFileOrEmpty(excludePath);
    assert.ok(content.includes(STEALTH_MARKER_START), 'exclude should contain stealth start marker');
    assert.ok(content.includes(STEALTH_MARKER_END), 'exclude should contain stealth end marker');
    for (const p of STEALTH_PATHS) {
      assert.ok(content.includes(p), `exclude should contain ${p}`);
    }

    cleanup(dir);
  });

  it('stealth enable with gitignore target writes block to .gitignore', () => {
    const { dir, gitignorePath, excludePath } = createTestRepo({
      'stealth.enabled': 'true',
      'stealth.ignore_target': 'gitignore',
    });

    runGenerateGitignore(dir);

    const giContent = readFileOrEmpty(gitignorePath);
    assert.ok(giContent.includes(STEALTH_MARKER_START), '.gitignore should contain stealth marker');
    for (const p of STEALTH_PATHS) {
      assert.ok(giContent.includes(p), `.gitignore should contain ${p}`);
    }

    // exclude should NOT have stealth block
    const exContent = readFileOrEmpty(excludePath);
    assert.ok(!exContent.includes(STEALTH_MARKER_START), 'exclude should NOT contain stealth marker');

    cleanup(dir);
  });

  it('stealth disable removes block and restores normal gitignore', () => {
    const { dir, excludePath, gitignorePath } = createTestRepo({
      'stealth.enabled': 'true',
    });

    // First enable stealth
    runGenerateGitignore(dir);
    assert.ok(readFileOrEmpty(excludePath).includes(STEALTH_MARKER_START), 'stealth should be enabled');

    // Now disable
    const configPath = path.join(dir, 'tricycle.config.yml');
    let config = fs.readFileSync(configPath, 'utf-8');
    config = config.replace('enabled: true', 'enabled: false');
    fs.writeFileSync(configPath, config);

    runGenerateGitignore(dir);

    // Stealth block should be gone from exclude
    assert.ok(!readFileOrEmpty(excludePath).includes(STEALTH_MARKER_START), 'stealth block should be removed from exclude');

    // Normal block should be in .gitignore
    const giContent = readFileOrEmpty(gitignorePath);
    assert.ok(giContent.includes('.claude/*'), '.gitignore should have normal .claude/* rule');
    assert.ok(giContent.includes('!.claude/settings.json'), '.gitignore should have negation rules');

    cleanup(dir);
  });

  it('target switch cleans old target and writes to new target', () => {
    const { dir, excludePath, gitignorePath, configPath } = createTestRepo({
      'stealth.enabled': 'true',
      'stealth.ignore_target': 'exclude',
    });

    // Write to exclude first
    runGenerateGitignore(dir);
    assert.ok(readFileOrEmpty(excludePath).includes(STEALTH_MARKER_START));

    // Switch to gitignore target
    let config = fs.readFileSync(configPath, 'utf-8');
    config = config.replace('ignore_target: exclude', 'ignore_target: gitignore');
    fs.writeFileSync(configPath, config);

    runGenerateGitignore(dir);

    // Old target cleaned
    assert.ok(!readFileOrEmpty(excludePath).includes(STEALTH_MARKER_START), 'exclude should be cleaned');
    // New target has block
    assert.ok(readFileOrEmpty(gitignorePath).includes(STEALTH_MARKER_START), '.gitignore should have stealth block');

    cleanup(dir);
  });

  it('idempotent — running twice does not duplicate the block', () => {
    const { dir, excludePath } = createTestRepo({
      'stealth.enabled': 'true',
    });

    runGenerateGitignore(dir);
    runGenerateGitignore(dir);

    const content = readFileOrEmpty(excludePath);
    const count = (content.match(/# >>> tricycle stealth/g) || []).length;
    assert.equal(count, 1, 'stealth block should appear exactly once');

    cleanup(dir);
  });

  it('preserves user rules in target file', () => {
    const { dir, excludePath } = createTestRepo({
      'stealth.enabled': 'true',
    });

    // Write user rules to exclude before stealth
    fs.mkdirSync(path.dirname(excludePath), { recursive: true });
    fs.writeFileSync(excludePath, '# My custom rules\n*.secret\nmy-local-file.txt\n');

    runGenerateGitignore(dir);

    const content = readFileOrEmpty(excludePath);
    assert.ok(content.includes('*.secret'), 'user rule *.secret should be preserved');
    assert.ok(content.includes('my-local-file.txt'), 'user rule my-local-file.txt should be preserved');
    assert.ok(content.includes(STEALTH_MARKER_START), 'stealth block should be present');

    cleanup(dir);
  });

  it('stealth block contains all required paths', () => {
    const { dir, excludePath } = createTestRepo({
      'stealth.enabled': 'true',
    });

    runGenerateGitignore(dir);

    const content = readFileOrEmpty(excludePath);
    for (const p of STEALTH_PATHS) {
      assert.ok(content.includes(p), `stealth block must contain: ${p}`);
    }

    cleanup(dir);
  });
});
