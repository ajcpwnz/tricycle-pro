import { describe, it, before, after } from 'node:test';
import { execFileSync } from 'node:child_process';
import { strictEqual, ok } from 'node:assert';
import { existsSync, readFileSync, statSync, readdirSync, rmSync, mkdtempSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { parse as parseYAML } from 'yaml';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const CLI = join(ROOT, 'bin/tricycle.js');

function run(...args) {
  return execFileSync('node', [CLI, ...args], {
    encoding: 'utf-8',
    cwd: ROOT,
    env: { ...process.env, NO_COLOR: '1' },
  });
}

function runIn(cwd, args, opts = {}) {
  return execFileSync('node', [CLI, ...args], {
    encoding: 'utf-8',
    cwd,
    env: { ...process.env, NO_COLOR: '1' },
    ...opts,
  });
}

function runInStatus(cwd, args, opts = {}) {
  try {
    const stdout = runIn(cwd, args, opts);
    return { stdout, code: 0 };
  } catch (e) {
    return { stdout: e.stdout || '', stderr: e.stderr || '', code: e.status };
  }
}

function runStatus(...args) {
  try {
    const stdout = run(...args);
    return { stdout, code: 0 };
  } catch (e) {
    return { stdout: e.stdout || '', stderr: e.stderr || '', code: e.status };
  }
}

// ─── Existing Tests ────────────────────────────────────────────────────────

describe('tricycle CLI', () => {
  it('--help exits 0 and prints usage', () => {
    const out = run('--help');
    ok(out.includes('Usage:'));
    ok(out.includes('tricycle init'));
    ok(out.includes('tricycle validate'));
  });

  it('unknown command exits 1', () => {
    const { code } = runStatus('bogus');
    strictEqual(code, 1);
  });

  it('validate succeeds on this repo', () => {
    const out = run('validate');
    ok(out.includes('All checks passed'));
  });

  it('update --dry-run exits cleanly', () => {
    const out = run('update', '--dry-run');
    ok(out.includes('DRY RUN'));
  });
});

describe('core files integrity', () => {
  it('all hook scripts are executable', () => {
    const hooksDir = join(ROOT, 'core/hooks');
    for (const f of readdirSync(hooksDir)) {
      if (f.endsWith('.sh')) {
        const stat = statSync(join(hooksDir, f));
        ok(stat.mode & 0o111, `${f} should be executable`);
      }
    }
  });

  it('all command templates exist', () => {
    const cmdsDir = join(ROOT, 'core/commands');
    const expected = [
      'trc.analyze.md', 'trc.checklist.md', 'trc.clarify.md',
      'trc.constitution.md', 'trc.headless.md', 'trc.implement.md',
      'trc.plan.md', 'trc.specify.md', 'trc.tasks.md',
      'trc.taskstoissues.md',
    ];
    for (const cmd of expected) {
      ok(existsSync(join(cmdsDir, cmd)), `missing command: ${cmd}`);
    }
  });

  it('all presets have valid YAML configs', () => {
    const presetsDir = join(ROOT, 'presets');
    for (const preset of readdirSync(presetsDir)) {
      const configPath = join(presetsDir, preset, 'tricycle.config.yml');
      if (existsSync(configPath)) {
        const content = readFileSync(configPath, 'utf-8');
        const config = parseYAML(content);
        ok(config.project?.name, `preset ${preset} missing project.name`);
        ok(config.project?.type, `preset ${preset} missing project.type`);
      }
    }
  });

  it('every preset directory has a tricycle.config.yml', () => {
    const presetsDir = join(ROOT, 'presets');
    for (const preset of readdirSync(presetsDir)) {
      const configPath = join(presetsDir, preset, 'tricycle.config.yml');
      ok(existsSync(configPath), `preset "${preset}" missing tricycle.config.yml`);
    }
  });

  it('no hardcoded project names in hooks', () => {
    const hooksDir = join(ROOT, 'core/hooks');
    for (const f of readdirSync(hooksDir)) {
      if (f.endsWith('.sh')) {
        const content = readFileSync(join(hooksDir, f), 'utf-8');
        ok(!content.includes('polst'), `${f} contains hardcoded "polst" reference`);
      }
    }
  });

  it('all modules have a README', () => {
    const modulesDir = join(ROOT, 'modules');
    for (const mod of readdirSync(modulesDir)) {
      const modPath = join(modulesDir, mod);
      if (statSync(modPath).isDirectory()) {
        ok(existsSync(join(modPath, 'README.md')), `module "${mod}" missing README.md`);
      }
    }
  });
});

// ─── Init Tests ────────────────────────────────────────────────────────────

describe('tricycle init --preset', () => {
  let tmpDir;

  before(() => {
    tmpDir = mkdtempSync(join(tmpdir(), 'trc-test-init-'));
  });

  after(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('creates tricycle.config.yml from single-app preset', () => {
    runIn(tmpDir, ['init', '--preset', 'single-app'], { input: 'test-project\n' });
    ok(existsSync(join(tmpDir, 'tricycle.config.yml')));
    const config = parseYAML(readFileSync(join(tmpDir, 'tricycle.config.yml'), 'utf-8'));
    strictEqual(config.project.name, 'test-project');
    strictEqual(config.project.type, 'single-app');
  });

  it('installs .claude/settings.json', () => {
    ok(existsSync(join(tmpDir, '.claude/settings.json')));
    const settings = JSON.parse(readFileSync(join(tmpDir, '.claude/settings.json'), 'utf-8'));
    ok(settings.permissions?.allow?.length > 0, 'settings should have permissions');
  });

  it('installs hook scripts as executable', () => {
    const hooksDir = join(tmpDir, '.claude/hooks');
    ok(existsSync(hooksDir), '.claude/hooks should exist');
    for (const f of readdirSync(hooksDir)) {
      if (f.endsWith('.sh')) {
        const stat = statSync(join(hooksDir, f));
        ok(stat.mode & 0o111, `installed ${f} should be executable`);
      }
    }
  });

  it('installs command templates', () => {
    const cmdsDir = join(tmpDir, '.claude/commands');
    ok(existsSync(cmdsDir), '.claude/commands should exist');
    ok(existsSync(join(cmdsDir, 'trc.specify.md')));
    ok(existsSync(join(cmdsDir, 'trc.implement.md')));
    ok(existsSync(join(cmdsDir, 'trc.headless.md')));
  });

  it('creates .tricycle.lock', () => {
    ok(existsSync(join(tmpDir, '.tricycle.lock')));
    const lock = JSON.parse(readFileSync(join(tmpDir, '.tricycle.lock'), 'utf-8'));
    ok(Object.keys(lock.files).length > 0, 'lock should track files');
  });

  it('creates constitution placeholder', () => {
    ok(existsSync(join(tmpDir, '.trc/memory/constitution.md')));
  });
});

describe('tricycle init errors', () => {
  it('invalid preset exits 1 and lists available presets', () => {
    const tmpDir = mkdtempSync(join(tmpdir(), 'trc-test-err-'));
    try {
      const { code, stderr } = runInStatus(tmpDir, ['init', '--preset', 'nonexistent']);
      strictEqual(code, 1);
      ok(stderr.includes('not found') || stderr.includes('Available'));
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it('express-prisma preset initializes successfully', () => {
    const tmpDir = mkdtempSync(join(tmpdir(), 'trc-test-ep-'));
    try {
      runIn(tmpDir, ['init', '--preset', 'express-prisma'], { input: 'my-api\n' });
      ok(existsSync(join(tmpDir, 'tricycle.config.yml')));
      const config = parseYAML(readFileSync(join(tmpDir, 'tricycle.config.yml'), 'utf-8'));
      strictEqual(config.project.name, 'my-api');
      strictEqual(config.mcp.preset, 'backend-only');
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});

// ─── Add Module Tests ──────────────────────────────────────────────────────

describe('tricycle add', () => {
  let tmpDir;

  before(() => {
    tmpDir = mkdtempSync(join(tmpdir(), 'trc-test-add-'));
    runIn(tmpDir, ['init', '--preset', 'single-app'], { input: 'test-add\n' });
  });

  after(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('add ci-watch installs commands', () => {
    runIn(tmpDir, ['add', 'ci-watch']);
    ok(existsSync(join(tmpDir, '.claude/commands/wait-ci.md')));
  });

  it('add memory installs seed files', () => {
    runIn(tmpDir, ['add', 'memory']);
    ok(existsSync(join(tmpDir, '.claude/memory/seeds/push-gating.md')));
    ok(existsSync(join(tmpDir, '.claude/memory/seeds/lint-test-before-done.md')));
  });

  it('add nonexistent module exits 1', () => {
    const { code } = runInStatus(tmpDir, ['add', 'nonexistent']);
    strictEqual(code, 1);
  });

  it('add without module name exits 1', () => {
    const { code } = runInStatus(tmpDir, ['add']);
    strictEqual(code, 1);
  });
});

// ─── Generate Tests ────────────────────────────────────────────────────────

describe('tricycle generate', () => {
  let tmpDir;

  before(() => {
    tmpDir = mkdtempSync(join(tmpdir(), 'trc-test-gen-'));
    runIn(tmpDir, ['init', '--preset', 'single-app'], { input: 'gen-test\n' });
  });

  after(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('generate claude-md creates CLAUDE.md with project name', () => {
    runIn(tmpDir, ['generate', 'claude-md']);
    ok(existsSync(join(tmpDir, 'CLAUDE.md')));
    const content = readFileSync(join(tmpDir, 'CLAUDE.md'), 'utf-8');
    ok(content.includes('gen-test'), 'CLAUDE.md should contain project name');
  });

  it('generate claude-md includes push gating section', () => {
    const content = readFileSync(join(tmpDir, 'CLAUDE.md'), 'utf-8');
    ok(content.includes('Push Gating') || content.includes('push'),
      'CLAUDE.md should include push gating');
  });

  it('generated settings.json always includes npx permission', () => {
    const settings = JSON.parse(readFileSync(join(tmpDir, '.claude/settings.json'), 'utf-8'));
    ok(settings.permissions.allow.includes('Bash(npx:*)'),
      'settings should include Bash(npx:*)');
  });

  it('generated settings.json includes npm permission', () => {
    const settings = JSON.parse(readFileSync(join(tmpDir, '.claude/settings.json'), 'utf-8'));
    ok(settings.permissions.allow.includes('Bash(npm:*)'),
      'settings should include Bash(npm:*)');
  });

  it('generate without config exits 1', () => {
    const emptyDir = mkdtempSync(join(tmpdir(), 'trc-test-noconf-'));
    try {
      const { code } = runInStatus(emptyDir, ['generate', 'claude-md']);
      strictEqual(code, 1);
    } finally {
      rmSync(emptyDir, { recursive: true, force: true });
    }
  });
});
