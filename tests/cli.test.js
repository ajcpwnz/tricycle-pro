import { describe, it } from 'node:test';
import { execFileSync } from 'node:child_process';
import { strictEqual, ok } from 'node:assert';
import { existsSync, readFileSync, statSync, readdirSync, mkdirSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
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

function runStatus(...args) {
  try {
    const stdout = run(...args);
    return { stdout, code: 0 };
  } catch (e) {
    return { stdout: e.stdout || '', stderr: e.stderr || '', code: e.status };
  }
}

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
});
