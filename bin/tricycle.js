#!/usr/bin/env node

import { parseArgs } from 'node:util';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync, writeFileSync, existsSync, mkdirSync, copyFileSync, readdirSync, statSync, chmodSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createInterface } from 'node:readline';
import YAML from 'yaml';

const __dirname = dirname(fileURLToPath(import.meta.url));
const TOOLKIT_ROOT = resolve(__dirname, '..');
const CWD = process.cwd();

// ─── Helpers ────────────────────────────────────────────────────────────────

function read(path) {
  return readFileSync(path, 'utf-8');
}

function write(path, content) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content, 'utf-8');
}

function sha256(content) {
  return createHash('sha256').update(content).digest('hex').slice(0, 16);
}

function copyRecursive(src, dest) {
  if (!existsSync(src)) return;
  const stat = statSync(src);
  if (stat.isDirectory()) {
    mkdirSync(dest, { recursive: true });
    for (const entry of readdirSync(src)) {
      copyRecursive(join(src, entry), join(dest, entry));
    }
  } else {
    mkdirSync(dirname(dest), { recursive: true });
    copyFileSync(src, dest);
    // Preserve executable bit for .sh files
    if (src.endsWith('.sh')) {
      chmodSync(dest, 0o755);
    }
  }
}

function loadConfig() {
  const configPath = join(CWD, 'tricycle.config.yml');
  if (!existsSync(configPath)) {
    console.error('Error: tricycle.config.yml not found in current directory.');
    console.error('Run `npx tricycle-pro init` to create one.');
    process.exit(1);
  }
  return YAML.parse(read(configPath));
}

function loadLock() {
  const lockPath = join(CWD, '.tricycle.lock');
  if (!existsSync(lockPath)) return { version: '0.1.0', installed: new Date().toISOString().slice(0, 10), files: {} };
  return JSON.parse(read(lockPath));
}

function saveLock(lock) {
  write(join(CWD, '.tricycle.lock'), JSON.stringify(lock, null, 2) + '\n');
}

function installFile(src, destRel, lock) {
  const dest = join(CWD, destRel);
  const content = read(src);
  const checksum = sha256(content);

  // Check if file exists and was locally modified
  if (existsSync(dest) && lock.files[destRel]) {
    const currentChecksum = sha256(read(dest));
    if (currentChecksum !== lock.files[destRel].checksum) {
      console.log(`  SKIP ${destRel} (locally modified)`);
      lock.files[destRel].customized = true;
      return false;
    }
  }

  write(dest, content);
  if (src.endsWith('.sh')) chmodSync(dest, 0o755);
  lock.files[destRel] = { checksum, customized: false };
  console.log(`  WRITE ${destRel}`);
  return true;
}

function installDir(srcDir, destRelDir, lock) {
  if (!existsSync(srcDir)) return;
  const entries = readdirSync(srcDir, { recursive: true });
  for (const entry of entries) {
    const srcPath = join(srcDir, entry);
    if (statSync(srcPath).isFile()) {
      installFile(srcPath, join(destRelDir, entry), lock);
    }
  }
}

async function prompt(question, defaultValue) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    const suffix = defaultValue ? ` [${defaultValue}]` : '';
    rl.question(`${question}${suffix}: `, (answer) => {
      rl.close();
      resolve(answer.trim() || defaultValue || '');
    });
  });
}

async function choose(question, options, defaultIdx = 0) {
  console.log(`\n${question}`);
  options.forEach((opt, i) => {
    const marker = i === defaultIdx ? '>' : ' ';
    console.log(`  ${marker} ${i + 1}. ${opt}`);
  });
  const answer = await prompt(`Choice (1-${options.length})`, String(defaultIdx + 1));
  const idx = parseInt(answer, 10) - 1;
  return idx >= 0 && idx < options.length ? idx : defaultIdx;
}

// ─── Commands ───────────────────────────────────────────────────────────────

async function cmdInit(args) {
  console.log('\n🔧 tricycle init — AI-driven spec-first development workflow\n');

  // Check for preset flag
  const presetName = args.values.preset;
  let config;

  if (presetName) {
    const presetPath = join(TOOLKIT_ROOT, 'presets', presetName, 'tricycle.config.yml');
    if (!existsSync(presetPath)) {
      console.error(`Error: preset "${presetName}" not found.`);
      const available = readdirSync(join(TOOLKIT_ROOT, 'presets')).filter(d =>
        existsSync(join(TOOLKIT_ROOT, 'presets', d, 'tricycle.config.yml'))
      );
      console.error(`Available: ${available.join(', ')}`);
      process.exit(1);
    }
    config = YAML.parse(read(presetPath));
    console.log(`Using preset: ${presetName}`);
    // Override project name
    config.project.name = await prompt('Project name', config.project.name || 'my-project');
  } else {
    // Interactive wizard
    const name = await prompt('Project name', 'my-project');
    const typeIdx = await choose('Project type:', ['monorepo', 'single-app'], 0);
    const type = ['monorepo', 'single-app'][typeIdx];
    const pmIdx = await choose('Package manager:', ['bun', 'npm', 'yarn', 'pnpm'], 0);
    const pm = ['bun', 'npm', 'yarn', 'pnpm'][pmIdx];
    const baseBranch = await prompt('Base branch (PR target)', 'staging');

    config = {
      project: { name, type, package_manager: pm, base_branch: baseBranch },
      apps: [],
      worktree: { enabled: true, path_pattern: `../{project}-{branch}`, db_isolation: false, env_copy: [] },
      mcp: { preset: 'minimal' },
      qa: { enabled: false },
      push: { require_approval: true, require_lint: true, require_tests: true, pr_target: baseBranch, auto_merge: true, merge_strategy: 'squash' },
      constitution: { root: '.specify/memory/constitution.md', per_app: type === 'monorepo', hierarchy: 'app-overrides-root' },
    };
  }

  // Write config
  const configContent = YAML.stringify(config, { lineWidth: 120 });
  write(join(CWD, 'tricycle.config.yml'), configContent);
  console.log('\n  WRITE tricycle.config.yml');

  // Install core files
  const lock = { version: '0.1.0', installed: new Date().toISOString().slice(0, 10), files: {} };
  console.log('\nInstalling core...');
  installDir(join(TOOLKIT_ROOT, 'core/commands'), '.claude/commands', lock);
  installDir(join(TOOLKIT_ROOT, 'core/templates'), '.specify/templates', lock);
  installDir(join(TOOLKIT_ROOT, 'core/scripts/bash'), '.specify/scripts/bash', lock);
  installDir(join(TOOLKIT_ROOT, 'core/hooks'), '.claude/hooks', lock);
  installDir(join(TOOLKIT_ROOT, 'core/skills'), '.claude/skills', lock);

  // Create constitution placeholder if it doesn't exist
  const constPath = join(CWD, '.specify/memory/constitution.md');
  if (!existsSync(constPath)) {
    write(constPath, '# Project Constitution\n\n_Run `/trc.constitution` to populate this file._\n');
    console.log('  WRITE .specify/memory/constitution.md (placeholder)');
  }

  // Generate settings.json
  cmdGenerateSettings(config, lock);

  // Update .gitignore
  cmdGenerateGitignore();

  saveLock(lock);
  console.log('\n✅ Tricycle Pro initialized. Next steps:');
  console.log('   1. Edit tricycle.config.yml to add your apps');
  console.log('   2. Run `npx tricycle-pro generate claude-md` to generate CLAUDE.md');
  console.log('   3. Run `/trc.constitution` in Claude Code to define project principles');
  console.log('   4. Run `npx tricycle-pro add <module>` to enable worktree, qa, ci-watch, mcp, or memory\n');
}

function cmdAdd(args) {
  const module = args.positionals[1];
  if (!module) {
    console.error('Usage: tricycle add <module>');
    console.error('Modules: worktree, qa, ci-watch, mcp, memory');
    process.exit(1);
  }

  const modulePath = join(TOOLKIT_ROOT, 'modules', module);
  if (!existsSync(modulePath)) {
    console.error(`Error: module "${module}" not found.`);
    process.exit(1);
  }

  const lock = loadLock();
  console.log(`\nInstalling module: ${module}`);

  // Install module files by category
  const subDirs = {
    commands: '.claude/commands',
    skills: '.claude/skills',
    hooks: '.claude/hooks',
    scripts: 'scripts',
    templates: '.specify/templates',
    adapters: 'scripts/adapters',
    seeds: '.claude/memory/seeds',
  };

  for (const [subDir, destDir] of Object.entries(subDirs)) {
    const srcDir = join(modulePath, subDir);
    if (existsSync(srcDir)) {
      installDir(srcDir, destDir, lock);
    }
  }

  // Copy README if present
  const readmeSrc = join(modulePath, 'README.md');
  if (existsSync(readmeSrc)) {
    console.log(`  INFO See ${module} docs: modules/${module}/README.md`);
  }

  // Module-specific post-install
  if (module === 'qa') {
    const qaDir = join(CWD, 'qa');
    if (!existsSync(qaDir)) {
      mkdirSync(qaDir, { recursive: true });
      console.log('  CREATE qa/ directory');
    }
    // Copy template files to qa/ if they don't exist
    const tplDir = join(modulePath, 'templates');
    if (existsSync(tplDir)) {
      for (const f of readdirSync(tplDir)) {
        const destName = f.replace('.tpl', '');
        const dest = join(qaDir, destName);
        if (!existsSync(dest)) {
          copyFileSync(join(tplDir, f), dest);
          console.log(`  WRITE qa/${destName}`);
        }
      }
    }
  }

  if (module === 'worktree') {
    // Install worktree scripts to project scripts/ dir
    const scriptsSrc = join(modulePath, 'scripts');
    if (existsSync(scriptsSrc)) {
      installDir(scriptsSrc, 'scripts', lock);
    }
  }

  saveLock(lock);
  console.log(`\n✅ Module "${module}" installed.\n`);
}

function cmdGenerate(args) {
  const target = args.positionals[1];
  const config = loadConfig();

  switch (target) {
    case 'claude-md':
      cmdGenerateClaudeMd(config);
      break;
    case 'settings':
      cmdGenerateSettings(config);
      break;
    case 'mcp':
      cmdGenerateMcp(config);
      break;
    default:
      console.error('Usage: tricycle generate <claude-md|settings|mcp>');
      process.exit(1);
  }
}

function cmdGenerateClaudeMd(config) {
  const sectionsDir = join(TOOLKIT_ROOT, 'generators/sections');
  const sections = [];

  // Always include commands section
  sections.push(renderSection(sectionsDir, 'commands.md.tpl', config));

  // Conditionally include sections based on config
  if (config.apps?.some(a => a.docker)) {
    sections.push(renderSection(sectionsDir, 'docker.md.tpl', config));
  }
  if (config.push?.require_lint || config.push?.require_tests) {
    sections.push(renderSection(sectionsDir, 'lint-test.md.tpl', config));
  }
  if (config.push?.require_approval) {
    sections.push(renderSection(sectionsDir, 'push-gating.md.tpl', config));
  }
  if (config.worktree?.enabled) {
    sections.push(renderSection(sectionsDir, 'worktree-workflow.md.tpl', config));
  }
  if (config.qa?.enabled) {
    sections.push(renderSection(sectionsDir, 'qa-testing.md.tpl', config));
  }
  if (config.mcp) {
    sections.push(renderSection(sectionsDir, 'mcp-usage.md.tpl', config));
  }
  sections.push(renderSection(sectionsDir, 'feature-branch-pr.md.tpl', config));
  sections.push(renderSection(sectionsDir, 'artifact-cleanup.md.tpl', config));

  const claudeMd = `# ${config.project.name}\n\n${sections.filter(Boolean).join('\n\n---\n\n')}\n`;
  write(join(CWD, 'CLAUDE.md'), claudeMd);
  console.log('  WRITE CLAUDE.md');
}

function renderSection(sectionsDir, tplName, config) {
  const tplPath = join(sectionsDir, tplName);
  if (!existsSync(tplPath)) return null;
  let content = read(tplPath);
  // Simple template variable substitution
  content = substituteVars(content, config);
  return content;
}

function substituteVars(template, config) {
  return template
    .replace(/\{\{project\.name\}\}/g, config.project?.name || 'my-project')
    .replace(/\{\{project\.package_manager\}\}/g, config.project?.package_manager || 'npm')
    .replace(/\{\{project\.base_branch\}\}/g, config.project?.base_branch || 'main')
    .replace(/\{\{push\.pr_target\}\}/g, config.push?.pr_target || config.project?.base_branch || 'main')
    .replace(/\{\{push\.merge_strategy\}\}/g, config.push?.merge_strategy || 'squash')
    .replace(/\{\{qa\.primary_tool\}\}/g, config.qa?.primary_tool || 'chrome-devtools')
    .replace(/\{\{qa\.fallback_tool\}\}/g, config.qa?.fallback_tool || 'playwright')
    .replace(/\{\{qa\.results_dir\}\}/g, config.qa?.results_dir || 'qa/results-{date}')
    .replace(/\{\{#each apps\}\}([\s\S]*?)\{\{\/each\}\}/g, (_, block) => {
      return (config.apps || []).map(app => substituteAppVars(block, app)).join('\n');
    })
    .replace(/\{\{#if ([\w.]+)\}\}([\s\S]*?)\{\{\/if\}\}/g, (_, key, block) => {
      const val = key.split('.').reduce((obj, k) => obj?.[k], config);
      return val ? block : '';
    });
}

function substituteAppVars(template, app) {
  return template
    .replace(/\{\{app\.name\}\}/g, app.name || '')
    .replace(/\{\{app\.path\}\}/g, app.path || '')
    .replace(/\{\{app\.lint\}\}/g, app.lint || '')
    .replace(/\{\{app\.test\}\}/g, app.test || '')
    .replace(/\{\{app\.build\}\}/g, app.build || '')
    .replace(/\{\{app\.dev\}\}/g, app.dev || '')
    .replace(/\{\{app\.port\}\}/g, String(app.port || ''));
}

function cmdGenerateSettings(config, lock) {
  // Core permissions every project needs
  const permissions = [
    'Edit', 'Write',
    'Bash(git:*)', 'Bash(cd:*)', 'Bash(ls:*)', 'Bash(cp:*)', 'Bash(mkdir:*)',
  ];

  // Package manager permissions
  const pm = config.project?.package_manager || 'npm';
  permissions.push(`Bash(${pm}:*)`);
  if (pm === 'bun') permissions.push('Bash(bunx:*)');
  if (pm !== 'npm') permissions.push('Bash(npx:*)');
  permissions.push('Bash(node:*)');

  // Docker permissions if any app uses docker
  if (config.apps?.some(a => a.docker)) {
    permissions.push('Bash(docker:*)', 'Bash(docker compose:*)');
  }

  // Script permissions
  permissions.push('Bash(./scripts:*)');

  // Turbo if monorepo
  if (config.project?.type === 'monorepo') {
    permissions.push('Bash(turbo:*)');
  }

  // Build hooks config
  const hooks = { PreToolUse: [], PostToolUse: [] };

  // Always add block-spec-in-main
  hooks.PreToolUse.push({
    matcher: 'Write|Edit',
    hooks: [{ type: 'command', command: '.claude/hooks/block-spec-in-main.sh', timeout: 5 }]
  });

  // Worktree hooks
  if (config.worktree?.enabled) {
    hooks.PreToolUse.push({
      matcher: 'Bash',
      hooks: [{ type: 'command', command: '.claude/hooks/block-branch-in-main.sh', timeout: 5 }]
    });
  }

  // Post-implement lint hook
  hooks.PostToolUse.push({
    matcher: 'Skill',
    hooks: [{ type: 'command', command: '.claude/hooks/post-implement-lint.sh', timeout: 5 }]
  });

  const settings = { permissions: { allow: permissions }, hooks };

  write(join(CWD, '.claude/settings.json'), JSON.stringify(settings, null, 2) + '\n');
  console.log('  WRITE .claude/settings.json');
}

function cmdGenerateMcp(config) {
  const mcpConfig = { mcpServers: {} };

  // Load preset if specified
  if (config.mcp?.preset) {
    const presetPath = join(TOOLKIT_ROOT, 'modules/mcp/presets', `${config.mcp.preset}.json`);
    if (existsSync(presetPath)) {
      const preset = JSON.parse(read(presetPath));
      Object.assign(mcpConfig.mcpServers, preset);
    }
  }

  // Merge custom servers
  if (config.mcp?.custom) {
    for (const [name, serverConfig] of Object.entries(config.mcp.custom)) {
      if (serverConfig.type === 'http') {
        mcpConfig.mcpServers[name] = { type: 'http', url: serverConfig.url };
      } else {
        mcpConfig.mcpServers[name] = {
          command: serverConfig.command || 'npx',
          args: serverConfig.args || [],
          ...(serverConfig.env ? { env: serverConfig.env } : {}),
        };
      }
    }
  }

  write(join(CWD, '.mcp.json'), JSON.stringify(mcpConfig, null, 2) + '\n');
  console.log('  WRITE .mcp.json');
}

function cmdGenerateGitignore() {
  const gitignorePath = join(CWD, '.gitignore');
  const claudeIgnoreBlock = [
    '',
    '# Claude Code — keep settings.json, commands, hooks, skills committed',
    '.claude/*',
    '!.claude/settings.json',
    '!.claude/commands/',
    '!.claude/hooks/',
    '!.claude/skills/',
    '',
    '# Tricycle Pro lock',
    '.tricycle.lock',
  ].join('\n');

  if (existsSync(gitignorePath)) {
    const existing = read(gitignorePath);
    if (!existing.includes('.claude/*')) {
      write(gitignorePath, existing + '\n' + claudeIgnoreBlock + '\n');
      console.log('  UPDATE .gitignore (appended .claude rules)');
    }
  } else {
    write(gitignorePath, claudeIgnoreBlock + '\n');
    console.log('  WRITE .gitignore');
  }
}

function cmdUpdate() {
  const lock = loadLock();
  const dryRun = process.argv.includes('--dry-run');

  if (dryRun) console.log('\n[DRY RUN] Showing what would change:\n');
  else console.log('\nUpdating Tricycle Pro files...\n');

  let updated = 0, skipped = 0, added = 0;

  // Check all core files
  const coreMappings = [
    ['core/commands', '.claude/commands'],
    ['core/templates', '.specify/templates'],
    ['core/scripts/bash', '.specify/scripts/bash'],
    ['core/hooks', '.claude/hooks'],
  ];

  for (const [srcRel, destRel] of coreMappings) {
    const srcDir = join(TOOLKIT_ROOT, srcRel);
    if (!existsSync(srcDir)) continue;
    for (const entry of readdirSync(srcDir, { recursive: true })) {
      const srcPath = join(srcDir, entry);
      if (!statSync(srcPath).isFile()) continue;
      const destRelPath = join(destRel, entry);
      const destPath = join(CWD, destRelPath);
      const newContent = read(srcPath);
      const newChecksum = sha256(newContent);

      if (!existsSync(destPath)) {
        if (dryRun) console.log(`  ADD ${destRelPath}`);
        else installFile(srcPath, destRelPath, lock);
        added++;
      } else if (lock.files[destRelPath]) {
        const currentChecksum = sha256(read(destPath));
        if (currentChecksum !== lock.files[destRelPath].checksum) {
          console.log(`  SKIP ${destRelPath} (locally modified)`);
          skipped++;
        } else if (newChecksum !== lock.files[destRelPath].checksum) {
          if (dryRun) console.log(`  UPDATE ${destRelPath}`);
          else installFile(srcPath, destRelPath, lock);
          updated++;
        }
      }
    }
  }

  if (!dryRun) saveLock(lock);
  console.log(`\n${dryRun ? 'Would: ' : ''}${updated} updated, ${added} added, ${skipped} skipped (locally modified)\n`);
}

function cmdValidate() {
  const config = loadConfig();
  let errors = 0;

  console.log('\nValidating Tricycle Pro configuration...\n');

  // Check required fields
  if (!config.project?.name) { console.error('  ✗ project.name is required'); errors++; }
  if (!config.project?.type) { console.error('  ✗ project.type is required'); errors++; }
  else console.log(`  ✓ project.type: ${config.project.type}`);

  // Check app paths exist
  for (const app of (config.apps || [])) {
    const appPath = join(CWD, app.path);
    if (!existsSync(appPath)) { console.error(`  ✗ app "${app.name}" path not found: ${app.path}`); errors++; }
    else console.log(`  ✓ app "${app.name}": ${app.path}`);
  }

  // Check core files installed
  const coreDirs = ['.claude/commands', '.specify/templates', '.specify/scripts/bash', '.claude/hooks'];
  for (const dir of coreDirs) {
    const fullPath = join(CWD, dir);
    if (!existsSync(fullPath)) { console.error(`  ✗ missing: ${dir}`); errors++; }
    else console.log(`  ✓ ${dir}`);
  }

  // Check constitution exists
  const constPath = join(CWD, config.constitution?.root || '.specify/memory/constitution.md');
  if (!existsSync(constPath)) { console.error(`  ✗ constitution not found: ${config.constitution?.root}`); errors++; }
  else console.log(`  ✓ constitution: ${config.constitution?.root}`);

  // Check scripts are executable
  const hookDir = join(CWD, '.claude/hooks');
  if (existsSync(hookDir)) {
    for (const f of readdirSync(hookDir)) {
      if (f.endsWith('.sh')) {
        try {
          const stat = statSync(join(hookDir, f));
          if (!(stat.mode & 0o111)) { console.error(`  ✗ not executable: .claude/hooks/${f}`); errors++; }
          else console.log(`  ✓ executable: .claude/hooks/${f}`);
        } catch { errors++; }
      }
    }
  }

  console.log(`\n${errors === 0 ? '✅ All checks passed.' : `❌ ${errors} error(s) found.`}\n`);
  process.exit(errors > 0 ? 1 : 0);
}

// ─── Main ───────────────────────────────────────────────────────────────────

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    preset: { type: 'string' },
    'dry-run': { type: 'boolean', default: false },
    'seed-memory': { type: 'boolean', default: false },
    help: { type: 'boolean', short: 'h', default: false },
  },
});

const command = positionals[0];

if (!command || values.help) {
  console.log(`
Tricycle Pro — AI-driven, spec-first development workflow toolkit

Usage:
  tricycle init [--preset <name>]     Initialize project with Tricycle Pro
  tricycle add <module>               Add optional module (worktree, qa, ci-watch, mcp, memory)
  tricycle generate <target>          Generate files (claude-md, settings, mcp)
  tricycle update [--dry-run]         Update core files to latest version
  tricycle validate                   Validate configuration and installed files

Options:
  --preset <name>     Use a preset configuration (monorepo-turborepo, nextjs-prisma, single-app)
  --seed-memory       Bootstrap memory files with universal best practices
  --dry-run           Show what would change without making changes
  -h, --help          Show this help message
`);
  process.exit(0);
}

switch (command) {
  case 'init':
    await cmdInit({ values, positionals });
    break;
  case 'add':
    cmdAdd({ values, positionals });
    break;
  case 'generate':
    cmdGenerate({ values, positionals });
    break;
  case 'update':
    cmdUpdate();
    break;
  case 'validate':
    cmdValidate();
    break;
  default:
    console.error(`Unknown command: ${command}. Run "tricycle --help" for usage.`);
    process.exit(1);
}
