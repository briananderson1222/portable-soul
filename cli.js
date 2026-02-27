#!/usr/bin/env node

/**
 * Portable Soul CLI
 *
 * Usage:
 *   npx portable-soul              # Install
 *   npx portable-soul --update     # Update soul-protocol.md to latest
 *   npx portable-soul --dir PATH   # Install to custom directory
 *   npx portable-soul --yes        # Non-interactive mode
 *   npx portable-soul --help       # Show help
 *   npx portable-soul symlinks              # Show symlink status
 *   npx portable-soul symlinks --sync       # Sync symlinks from config
 *   npx portable-soul symlinks --remove     # Remove all symlinks
 *   npx portable-soul symlinks --sync --dry-run    # Dry-run sync
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync, spawn } = require('child_process');
const readline = require('readline');

// ── Colors ──────────────────────────────────────────────────────────

const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  dim: '\x1b[2m',
  green: '\x1b[32m',
  blue: '\x1b[34m',
  yellow: '\x1b[33m',
  cyan: '\x1b[36m',
  red: '\x1b[31m',
};

const c = (str, color) => `${colors[color]}${str}${colors.reset}`;

// ── Paths ───────────────────────────────────────────────────

const PACKAGE_DIR = __dirname;
const TEMPLATES_DIR = path.join(PACKAGE_DIR, 'templates', 'full');
const DEFAULT_SOUL_DIR = path.join(os.homedir(), '.soul');
const CONFIG_DIR = path.join(DEFAULT_SOUL_DIR, '.config');

// ── File categories ───────────────────────────────────────────

const SYSTEM_FILES = ['soul-protocol.md'];

const SEED_FILES = [
  'identity.md',
  'soul.md',
  'user.md',
  'system.md',
  'memory.md',
  'lessons.md',
  'preferences.md',
  'decisions.md',
  'continuity.md',
  'followups.md',
  'bookmarks.md',
];

// ── Options for CLI ───────────────────────────────────────────

let dryRun = false;
let nonInteractive = false;

// ── Helpers ──────────────────────────────────────────────────────────

function log(message, type = 'info') {
  const icons = {
    info: c('●', 'blue'),
    success: c('', 'green'),
    warn: c('!', 'yellow'),
    error: c('', 'red'),
  };
  console.log(`  ${icons[type] || icons.info} ${message}`);
}

function ask(prompt, defaultValue) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const hint = defaultValue != null ? ` ${c(`[${defaultValue}]`, 'dim')}` : '';
  return new Promise(resolve => {
    rl.question(`  ${c('?', 'cyan')} ${prompt}${hint}: `, answer => {
      rl.close();
      resolve(answer.trim() || defaultValue);
    });
  });
}

async function confirm(prompt, defaultValue = false) {
  const answer = await ask(prompt, defaultValue ? 'Y/n' : 'y/N');
  if (typeof answer === 'boolean') return answer;
  const a = String(answer).toLowerCase();
  if (a === 'y' || a === 'yes') return true;
  if (a === 'n' || a === 'no') return false;
  return defaultValue;
}

function git(args, opts = {}) {
  try {
    return execSync(`git ${args}`, {
      stdio: opts.silent ? 'pipe' : 'inherit',
      cwd: opts.cwd,
      encoding: 'utf-8',
    });
  } catch (e) {
    if (opts.ignoreError) return '';
    throw e;
  }
}

function isGitRepo(dir) {
  try {
    execSync('git rev-parse --git-dir', { cwd: dir, stdio: 'pipe' });
    return true;
  } catch { return false; }
}

function ensureDir(dir) {
  if (!dryRun) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function copyFile(src, dest) {
  if (!dryRun) {
    fs.copyFileSync(src, dest);
  }
}

function copyIfMissing(src, dest) {
  if (fs.existsSync(dest)) return false;
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    if (!dryRun) {
      fs.cpSync(src, dest, { recursive: true });
    }
  } else {
    copyFile(src, dest);
  }
  return true;
}

function resolvePath(p) {
  return p.replace(/^~/, os.homedir());
}

// ── Banner ──────────────────────────────────────────────────────────

function printBanner() {
  console.log();
  console.log(c('  ╔══════════════════════════════════════╗', 'cyan'));
  console.log(c('  ║', 'cyan') + c('  Portable Soul  ', 'bright') + c('Identity · Memory · Continuity', 'dim') + '     ' + c('║', 'cyan'));
  console.log(c('  ╚══════════════════════════════════════╝', 'cyan'));
  console.log();
}

// ── TOML Parsing (basic, no dependencies) ───────────────

function parseToml(content) {
  const result = { paths: {}, sync: {} };
  const lines = content.split('\n');
  let currentSection = null;
  let currentKey = null;

  for (let i = 0; i < lines.length; i++) {
    let line = lines[i].trim();

    // Skip comments and empty lines
    if (line.startsWith('#') || line === '') continue;

    // Section headers
    const sectionMatch = line.match(/^\[([^\]]+)\]$/);
    if (sectionMatch) {
      currentSection = sectionMatch[1];
      currentKey = null;
      continue;
    }

    // Key-value pairs
    const kvMatch = line.match(/^(\w+)\s*=\s*(.+)$/);
    if (kvMatch) {
      const key = kvMatch[1];
      let value = kvMatch[2].trim();

      // Parse values
      if (value.startsWith('"') && value.endsWith('"')) {
        value = value.slice(1, -1);
      } else if (value === 'true') {
        value = true;
      } else if (value === 'false') {
        value = false;
      } else if (value.startsWith('[') && value.endsWith(']')) {
        // Inline array
        value = value.slice(1, -1).split(',').map(v => v.trim().replace(/"/g, ''));
      } else if (!isNaN(value)) {
        value = Number(value);
      }

      if (currentSection === 'paths') {
        result.paths[key] = value;
      } else if (currentSection) {
        const [section, subsection] = currentSection.split('.');
        if (subsection) {
          if (!result[section]) result[section] = {};
          if (!result[section][subsection]) result[section][subsection] = {};
          result[section][subsection][key] = value;
        } else {
          result[currentSection] = result[currentSection] || {};
          result[currentSection][key] = value;
        }
      }
      continue;
    }

    // Multiline array continuation (basic support)
    if (currentKey && line.startsWith('-')) {
      const item = line.slice(1).trim().replace(/"/g, '');
      if (Array.isArray(result.paths[currentKey])) {
        result.paths[currentKey].push(item);
      }
    }
  }

  return result;
}

// ── Config loading ─────────────────────────────────────────────

function loadConfig() {
  const hostname = os.hostname().split('.')[0].toLowerCase();
  const machineConfig = path.join(CONFIG_DIR, `${hostname}.toml`);
  const defaultConfig = path.join(CONFIG_DIR, 'default.toml');

  const configPath = fs.existsSync(machineConfig) ? machineConfig :
                   fs.existsSync(defaultConfig) ? defaultConfig : null;

  if (!configPath) return { paths: {}, sync: {} };

  try {
    const content = fs.readFileSync(configPath, 'utf-8');
    return parseToml(content);
  } catch (e) {
    log(`Error reading config: ${e.message}`, 'error');
    return { paths: {}, sync: {} };
  }
}

// ── Write default config ───────────────────────────────────────

function writeDefaultConfig(soulDir) {
  const configDir = path.join(soulDir, '.config');
  ensureDir(configDir);

  const defaultConfig = path.join(configDir, 'default.toml');
  if (fs.existsSync(defaultConfig)) {
    log('Skipped default.toml (already exists)', 'info');
    return;
  }

  const content = `# Portable Soul Configuration
# Copy this file to <hostname>.toml for machine-specific settings

# Path mappings for symlinks or sync
[paths]
# Map files from soul vault to external locations
# identity.md = "~/.config/claude/identity.md"
# memory.md = "~/.config/claude/memory.md"
# lessons.md = ["~/.config/kiro/lessons.md", "~/.config/claude/lessons.md"]

# Sync settings
[sync]
# How to sync: "link" (symlink), "copy" (file copy)
link_mode = "link"

# Sync provider: "copy", "rsync", "git-sync"
provider = "copy"

# Sync direction: "forward" (soul -> targets), "reverse" (targets -> soul), "bidirectional"
direction = "forward"

# Auto-sync after changes (not yet implemented)
auto = false

# Exclude patterns (glob-style)
exclude = [".DS_Store", "Thumbs.db", "*.tmp"]

# Dry-run mode (preview changes without applying)
dry_run = false

# Per-source overrides (optional)
# [sync.paths.identity.md]
# link_mode = "copy"
# direction = "bidirectional"
`;

  fs.writeFileSync(defaultConfig, content);
  log('Wrote default.toml', 'success');
}

// ── Sync providers ─────────────────────────────────────────────

async function syncCopy(source, target, direction) {
  const stats = {
    copied: 0,
    skipped: 0,
    errors: 0,
  };

  const sourceAbs = path.resolve(source);
  const targetAbs = resolvePath(target);

  try {
    const sourceStat = fs.statSync(sourceAbs);
    const sourceMtime = sourceStat.mtimeMs;

    if (direction === 'forward' || direction === 'bidirectional') {
      // Source -> Target
      if (fs.existsSync(targetAbs)) {
        const targetStat = fs.statSync(targetAbs);
        const targetMtime = targetStat.mtimeMs;
        if (sourceMtime > targetMtime) {
          if (!dryRun) {
            fs.copyFileSync(sourceAbs, targetAbs);
          }
          stats.copied++;
          log(`${c('→', 'dim')} ${c(target, 'dim')} (newer)`, 'info');
        } else {
          stats.skipped++;
        }
      } else {
        if (!dryRun) {
          ensureDir(path.dirname(targetAbs));
          fs.copyFileSync(sourceAbs, targetAbs);
        }
        stats.copied++;
        log(`${c('→', 'dim')} ${c(target, 'dim')} (new)`, 'info');
      }
    }

    if (direction === 'reverse' || direction === 'bidirectional') {
      // Target -> Source
      if (fs.existsSync(targetAbs)) {
        const targetStat = fs.statSync(targetAbs);
        const targetMtime = targetStat.mtimeMs;
        if (targetMtime > sourceMtime) {
          if (!dryRun) {
            fs.copyFileSync(targetAbs, sourceAbs);
          }
          stats.copied++;
          log(`${c('←', 'dim')} ${c(source, 'dim')} (newer from target)`, 'info');
        }
      }
    }

    return stats;
  } catch (e) {
    log(`Error syncing ${path.basename(source)}: ${e.message}`, 'error');
    stats.errors++;
    return stats;
  }
}

async function syncRsync(source, target, direction) {
  const stats = { copied: 0, skipped: 0, errors: 0 };

  try {
    // Check if rsync is available
    execSync('rsync --version', { stdio: 'pipe' });

    const sourceAbs = path.resolve(source);
    const targetAbs = resolvePath(target);

    let args = ['-a', '--update'];

    if (dryRun) {
      args.push('--dry-run');
    }

    if (direction === 'forward' || direction === 'bidirectional') {
      const cmd = `rsync ${args.join(' ')} ${sourceAbs} ${targetAbs}`;
      if (!dryRun) {
        execSync(cmd, { stdio: 'pipe' });
      }
      stats.copied++;
      log(`${c('rsync', 'cyan')} ${c('→', 'dim')} ${target}`, 'info');
    }

    if (direction === 'reverse') {
      const cmd = `rsync ${args.join(' ')} ${targetAbs} ${sourceAbs}`;
      if (!dryRun) {
        execSync(cmd, { stdio: 'pipe' });
      }
      stats.copied++;
      log(`${c('rsync', 'cyan')} ${c('←', 'dim')} ${target}`, 'info');
    }

    return stats;
  } catch (e) {
    if (e.message.includes('not found') || e.message.includes('command not found')) {
      log('rsync not available, falling back to copy', 'warn');
      return syncCopy(source, target, direction);
    }
    log(`rsync error: ${e.message}`, 'error');
    stats.errors++;
    return stats;
  }
}

// ── Path management ────────────────────────────────────────────

function linkStatus(source, target) {
  try {
    if (!fs.existsSync(source)) {
      return { status: 'source-missing', message: c('Source missing', 'red') };
    }

    if (!fs.existsSync(target)) {
      return { status: 'missing', message: c('Not linked', 'yellow') };
    }

    const targetStat = fs.lstatSync(target);
    const sourceStat = fs.statSync(source);

    if (targetStat.isSymbolicLink()) {
      const linkTarget = fs.readlinkSync(target);
      const linkTargetAbs = path.resolve(path.dirname(target), linkTarget);
      const sourceAbs = path.resolve(source);

      if (linkTargetAbs === sourceAbs) {
        return { status: 'ok', message: c('OK', 'green') };
      } else {
        return { status: 'mismatch', message: c('Points elsewhere', 'yellow') };
      }
    } else {
      // Target exists but is not a symlink
      if (targetStat.isSymbolicLink()) {
        return { status: 'ok', message: c('OK', 'green') };
      }
      return { status: 'file-not-link', message: c('File exists (not symlink)', 'yellow') };
    }
  } catch (e) {
    return { status: 'error', message: c(`Error: ${e.message}`, 'red') };
  }
}

function createLink(source, target, mode = 'link') {
  try {
    if (!fs.existsSync(source)) {
      log(`Source missing: ${source}`, 'error');
      return false;
    }

    const targetAbs = resolvePath(target);
    ensureDir(path.dirname(targetAbs));

    // Remove existing target
    if (fs.existsSync(targetAbs)) {
      fs.unlinkSync(targetAbs);
    }

    if (mode === 'link') {
      // Try symlink first
      try {
        fs.symlinkSync(path.resolve(source), targetAbs);
        return true;
      } catch (e) {
        if (e.code === 'EPERM' || e.code === 'EXDEV') {
          // Fallback to junction on Windows or copy
          log(`Symlink not supported, using copy`, 'warn');
        } else {
          throw e;
        }
      }
    }

    // Copy mode or fallback
    fs.copyFileSync(source, targetAbs);
    return true;
  } catch (e) {
    log(`Failed to create link: ${e.message}`, 'error');
    return false;
  }
}

function removeLink(target) {
  try {
    const targetAbs = resolvePath(target);
    if (fs.existsSync(targetAbs)) {
      fs.unlinkSync(targetAbs);
      return true;
    }
    return false;
  } catch (e) {
    log(`Failed to remove link: ${e.message}`, 'error');
    return false;
  }
}

// ── Symlink management ─────────────────────────────────────────

function showSymlinkStatus(soulDir) {
  const config = loadConfig();
  const sources = Object.keys(config.paths || {});

  if (sources.length === 0) {
    log('No paths configured', 'info');
    console.log(`  Edit ${path.join(CONFIG_DIR, 'default.toml')} to add [paths]`);
    console.log();
    return;
  }

  log('Path status:', 'info');
  console.log();

  for (const source of sources) {
    const sourceAbs = path.join(soulDir, source);
    const targets = Array.isArray(config.paths[source]) ? config.paths[source] : [config.paths[source]];

    const status = linkStatus(sourceAbs, resolvePath(targets[0]));
    console.log(`  ${c(source, 'bright')}`);
    console.log(`    ${status.message}`);

    if (targets.length > 1) {
      console.log(`    targets:`);
      for (let i = 0; i < targets.length; i++) {
        const abs = resolvePath(targets[i]);
        const isCurrent = i === 0 ? ' (current)' : '';
        console.log(`      ${c(abs, 'dim')}${isCurrent}`);
      }
      console.log();
    }
  }
}

async function syncSymlinks(soulDir, options = {}) {
  const config = loadConfig();
  const sync = config.sync || {};
  const sources = Object.keys(config.paths || {});

  if (sources.length === 0) {
    log('No paths configured', 'info');
    console.log(`  Edit ${path.join(CONFIG_DIR, 'default.toml')} to add [paths]`);
    console.log();
    return { created: 0, failed: 0, copied: 0, skipped: 0 };
  }

  const linkMode = options.mode || sync.link_mode || 'link';
  const provider = options.provider || sync.provider || 'copy';
  const direction = options.direction || sync.direction || 'forward';
  const exclude = options.exclude || sync.exclude || [];

  log(`Sync mode: ${c(linkMode, 'bright')}, provider: ${c(provider, 'bright')}, direction: ${c(direction, 'bright')}`);
  if (dryRun) log(c('DRY RUN - no changes will be made', 'yellow'));
  console.log();

  let created = 0, failed = 0, copied = 0, skipped = 0;

  for (const source of sources) {
    const sourceAbs = path.join(soulDir, source);

    if (!fs.existsSync(sourceAbs)) {
      log(`Source missing: ${source}`, 'error');
      failed++;
      continue;
    }

    const targets = Array.isArray(config.paths[source]) ? config.paths[source] : [config.paths[source]];

    for (const target of targets) {
      const targetAbs = resolvePath(target);

      // Check exclude patterns
      let excluded = false;
      for (const pattern of exclude) {
        if (path.basename(targetAbs).includes(pattern) || targetAbs.includes(pattern)) {
          excluded = true;
          break;
        }
      }

      if (excluded) {
        log(`Skipped (excluded): ${c(target, 'dim')}`, 'info');
        skipped++;
        continue;
      }

      if (linkMode === 'link') {
        const status = linkStatus(sourceAbs, targetAbs);

        if (status.status === 'ok' || status.status === 'file-not-link') {
          continue;
        }

        if (createLink(sourceAbs, targetAbs, linkMode)) {
          created++;
          log(`Created link: ${c(source, 'bright')} → ${c(targetAbs, 'dim')}`, 'success');
        } else {
          failed++;
        }
      } else {
        // Copy mode with sync provider
        const stats = provider === 'rsync'
          ? await syncRsync(sourceAbs, targetAbs, direction)
          : await syncCopy(sourceAbs, targetAbs, direction);
        copied += stats.copied;
        skipped += stats.skipped;
        failed += stats.errors;
      }
    }
  }

  console.log();
  if (created > 0) log(`Created ${created} link(s)`, 'success');
  if (copied > 0) log(`Copied ${copied} file(s)`, 'success');
  if (skipped > 0) log(`Skipped ${skipped}`, 'info');
  if (failed > 0) log(`Failed ${failed}`, 'error');

  return { created, failed, copied, skipped };
}

async function removeSymlinks(soulDir) {
  const config = loadConfig();
  const sources = Object.keys(config.paths || {});

  if (sources.length === 0) {
    log('No paths configured', 'info');
    return { removed: 0 };
  }

  if (!dryRun) {
    const answer = await confirm('Remove all linked paths?', false);
    if (!answer) {
      log('Cancelled', 'info');
      return { removed: 0 };
    }
  }

  let removed = 0;
  for (const source of sources) {
    const targets = Array.isArray(config.paths[source]) ? config.paths[source] : [config.paths[source]];
    for (const target of targets) {
      const targetAbs = resolvePath(target);
      if (removeLink(targetAbs)) {
        removed++;
        log(`Removed: ${c(targetAbs, 'dim')}`, 'info');
      }
    }
  }

  console.log();
  log(`Removed ${removed} path(s)`, 'success');
  return { removed };
}

// ── .gitignore ─────────────────────────────────────────────────────

function writeGitignore(soulDir, obsidian) {
  const lines = [
    '# Obsidian',
    '.obsidian/workspace.json',
    '.obsidian/workspace-mobile.json',
    '.obsidian/graph.json',
    '.trash/',
    '',
    '# OS',
    '.DS_Store',
    'Thumbs.db',
  ];
  if (!obsidian) {
    lines.unshift('.obsidian/');
  }
  fs.writeFileSync(path.join(soulDir, '.gitignore'), lines.join('\n') + '\n');
}

// ── Obsidian config ─────────────────────────────────────────────────

function updateConfigForObsidian(soulDir) {
  const configPath = path.join(soulDir, 'soul.config.yml');
  if (!fs.existsSync(configPath)) return;

  let content = fs.readFileSync(configPath, 'utf-8');

  content = content.replace(
    /^\s*provider:\s*plain\b/m,
    'provider: obsidian'
  );

  content = content.replace(
    /^\s*#\s*(features:\s*\[wikilinks.*\])\s*$/m,
    '$1'
  );

  fs.writeFileSync(configPath, content);
}

// ── Install ─────────────────────────────────────────────────────────

async function install(soulDir) {
  printBanner();
  log("Let's set up your portable AI soul!");
  console.log();

  // Check git
  try { execSync('git --version', { stdio: 'pipe' }); }
  catch {
    log('Git is required. Please install Git first.', 'error');
    process.exit(1);
  }

  // Ask directory (skip in non-interactive)
  if (!nonInteractive) {
    const chosenDir = await ask('Soul directory', soulDir);
    soulDir = path.resolve(chosenDir.replace(/^~/, os.homedir()));
  } else {
    soulDir = path.resolve(soulDir.replace(/^~/, os.homedir()));
  }

  // Detect existing install
  if (fs.existsSync(soulDir) && isGitRepo(soulDir) && fs.existsSync(path.join(soulDir, 'soul-protocol.md'))) {
    log(`Soul already installed at ${soulDir}`, 'warn');
    log('Use --update to update soul-protocol.md to latest version.', 'info');
    log('Manage paths with: npx portable-soul symlinks', 'info');
    return;
  }

  // Ask Obsidian (default to Yes in non-interactive)
  let useObsidian = true;
  if (!nonInteractive) {
    useObsidian = await confirm('Configure for Obsidian?', true);
  }

  console.log();
  log('Setup plan:');
  log(`  Directory:     ${c(soulDir, 'bright')}`);
  log(`  Obsidian:      ${useObsidian ? 'Yes' : 'No'}`);
  console.log();

  if (!nonInteractive) {
    const proceed = await confirm('Continue?', true);
    if (!proceed) { log('Cancelled.', 'warn'); return; }
  }

  console.log();

  // 1. Create directory
  ensureDir(soulDir);
  log(`Created ${soulDir}`, 'success');

  // 2. Git init
  if (!isGitRepo(soulDir)) {
    git('init', { cwd: soulDir, silent: true });
    log('Initialized git repo', 'success');
  } else {
    log('Git repo already initialized', 'success');
  }

  // 3. Copy system files (soul-protocol.md)
  for (const file of SYSTEM_FILES) {
    const src = path.join(TEMPLATES_DIR, file);
    if (!fs.existsSync(src)) continue;
    const dest = path.join(soulDir, file);
    copyFile(src, dest);
    log(`Copied ${file}`, 'success');
  }

  // 4. Copy seed files (skip existing)
  for (const file of SEED_FILES) {
    const src = path.join(TEMPLATES_DIR, file);
    if (!fs.existsSync(src)) continue;
    const dest = path.join(soulDir, file);
    if (copyIfMissing(src, dest)) {
      log(`Copied ${file}`, 'success');
    } else {
      log(`Skipped ${file} (already exists)`, 'info');
    }
  }

  // 5. Copy soul.config.yml (skip existing)
  {
    const src = path.join(PACKAGE_DIR, 'soul.config.yml');
    if (fs.existsSync(src)) {
      const dest = path.join(soulDir, 'soul.config.yml');
      if (copyIfMissing(src, dest)) {
        log('Copied soul.config.yml', 'success');
      } else {
        log('Skipped soul.config.yml (already exists)', 'info');
      }
    }
  }

  // 6. Create journal/ stub
  {
    const journalDir = path.join(soulDir, 'journal');
    if (!fs.existsSync(journalDir)) {
      ensureDir(journalDir);
      const readmeSrc = path.join(TEMPLATES_DIR, 'journal', 'README.md');
      if (fs.existsSync(readmeSrc)) {
        copyFile(readmeSrc, path.join(journalDir, 'README.md'));
      }
      log('Created journal/', 'success');
    } else {
      log('Skipped journal/ (already exists)', 'info');
    }
  }

  // 7. Obsidian config
  if (useObsidian) {
    updateConfigForObsidian(soulDir);
    log('Configured for Obsidian', 'success');
  }

  // 8. .gitignore
  writeGitignore(soulDir, useObsidian);
  log('Wrote .gitignore', 'success');

  // 9. Write default config
  writeDefaultConfig(soulDir);

  // 10. Initial commit
  git('add -A', { cwd: soulDir, silent: true });
  git('commit -m "Initial soul setup"', { cwd: soulDir, silent: true, ignoreError: true });
  log('Created initial commit', 'success');

  // 11. Next steps
  console.log();
  console.log(c('  ── Next steps ────────────────────────────────────', 'cyan'));
  console.log();

  log(`Open ${c(soulDir, 'bright')} in your editor`);
  log('Edit → core files to define your AI:');
  console.log(`     ${c('identity.md', 'bright')}   — personality, voice, values`);
  console.log(`     ${c('soul.md', 'bright')}       — philosophy and purpose`);
  console.log(`     ${c('user.md', 'bright')}       — your preferences and goals`);
  console.log(`     ${c('system.md', 'bright')}     — capabilities and rules`);
  console.log();

  if (useObsidian) {
    log(`Open ${c(soulDir, 'bright')} as an Obsidian vault`);
    console.log();
  }

  log(`Manage paths:`);
  log(`  npx portable-soul symlinks                      — Show status`);
  log(`  npx portable-soul symlinks --sync              — Sync paths`);
  log(`  npx portable-soul symlinks --sync --dry-run    — Preview sync`);
  log(`  npx portable-soul symlinks --remove            — Remove paths`);
  console.log();
  log(`Update anytime: ${c('npx portable-soul --update', 'bright')}`);
  console.log();
}

// ── Update ──────────────────────────────────────────────────────────────────

async function update(soulDir) {
  printBanner();

  // Find vault
  if (!fs.existsSync(soulDir)) {
    log(`Soul directory not found: ${soulDir}`, 'error');
    log('Run npx portable-soul first to install.', 'info');
    process.exit(1);
  }

  if (!fs.existsSync(path.join(soulDir, 'soul-protocol.md'))) {
    log('No soul-protocol.md found. Is this a soul directory?', 'error');
    process.exit(1);
  }

  // 1. Replace soul-protocol.md
  const src = path.join(TEMPLATES_DIR, 'soul-protocol.md');
  if (!fs.existsSync(src)) {
    log('Template file not found. This may be a development install.', 'warn');
  } else {
    const dest = path.join(soulDir, 'soul-protocol.md');
    const oldContent = fs.readFileSync(dest, 'utf-8');
    const newContent = fs.readFileSync(src, 'utf-8');

    if (oldContent === newContent) {
      log('soul-protocol.md is already up to date', 'success');
    } else {
      copyFile(src, dest);
      log('Updated soul-protocol.md', 'success');
    }
  }

  // 2. Check for new seed templates not in vault
  const newFiles = [];
  for (const file of SEED_FILES) {
    const fileSrc = path.join(TEMPLATES_DIR, file);
    if (!fs.existsSync(fileSrc)) continue;
    const fileDest = path.join(soulDir, file);
    if (!fs.existsSync(fileDest)) {
      newFiles.push(file);
    }
  }

  if (newFiles.length > 0) {
    console.log();
    log(`Found ${newFiles.length} new template(s) not in your vault:`);
    for (const f of newFiles) {
      console.log(`     ${c(f, 'bright')}`);
    }
    console.log();

    const shouldCopy = await confirm('Copy new templates?', true);
    if (shouldCopy) {
      for (const f of newFiles) {
        copyFile(path.join(TEMPLATES_DIR, f), path.join(soulDir, f));
        log(`Copied ${f}`, 'success');
      }
    }
  }

  // 3. Commit if changes
  if (isGitRepo(soulDir)) {
    const status = git('status --porcelain', { cwd: soulDir, silent: true }).trim();
    if (status) {
      git('add -A', { cwd: soulDir, silent: true });
      git('commit -m "soul: update soul-protocol.md"', { cwd: soulDir, silent: true, ignoreError: true });
      log('Committed changes', 'success');
    } else {
      log('No changes to commit', 'info');
    }
  }

  console.log();
  log('Your personal files are unchanged.', 'info');
  console.log();
}

// ── Help ─────────────────────────────────────────────────────────────

function printHelp() {
  printBanner();
  console.log('  Usage:');
  console.log();
  console.log(`    ${c('npx portable-soul', 'bright')}                              Install (create ~/.soul/)`);
  console.log(`    ${c('npx portable-soul --update', 'bright')}                     Update soul-protocol.md`);
  console.log(`    ${c('npx portable-soul --dir PATH', 'bright')}                   Install to custom directory`);
  console.log(`    ${c('npx portable-soul symlinks', 'bright')}                    Show path status`);
  console.log(`    ${c('npx portable-soul symlinks --sync', 'bright')}              Sync paths from config`);
  console.log(`    ${c('npx portable-soul symlinks --sync --mode copy', 'bright')}  Use copy mode`);
  console.log(`    ${c('npx portable-soul symlinks --sync --dry-run', 'bright')}    Preview sync`);
  console.log(`    ${c('npx portable-soul symlinks --remove', 'bright')}            Remove all paths`);
  console.log(`    ${c('npx portable-soul --help', 'bright')}                       Show this message`);
  console.log(`    ${c('npx portable-soul --yes', 'bright')}                        Non-interactive mode`);
  console.log();
  console.log('  Config file: ~/.soul/.config/default.toml');
  console.log('  Machine-specific: ~/.soul/.config/<hostname>.toml');
  console.log();
}

// ── Main ────────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);

  if (args.includes('--help') || args.includes('-h')) {
    printHelp();
    return;
  }

  // Check for --dry-run global flag
  dryRun = args.includes('--dry-run');
  nonInteractive = args.includes('--yes') || args.includes('-y');

  // Symlinks subcommand
  const symlinksIdx = args.indexOf('symlinks');
  if (symlinksIdx !== -1) {
    // Parse subcommand options
    const subArgs = args.slice(symlinksIdx + 1);
    const modeIdx = subArgs.indexOf('--mode');
    const providerIdx = subArgs.indexOf('--provider');
    const directionIdx = subArgs.indexOf('--direction');

    const options = {};
    if (modeIdx !== -1 && subArgs[modeIdx + 1]) {
      options.mode = subArgs[modeIdx + 1];
    }
    if (providerIdx !== -1 && subArgs[providerIdx + 1]) {
      options.provider = subArgs[providerIdx + 1];
    }
    if (directionIdx !== -1 && subArgs[directionIdx + 1]) {
      options.direction = subArgs[directionIdx + 1];
    }

    let soulDir = DEFAULT_SOUL_DIR;
    const dirIdx = args.indexOf('--dir');
    if (dirIdx !== -1 && args[dirIdx + 1]) {
      soulDir = path.resolve(args[dirIdx + 1].replace(/^~/, os.homedir()));
    }

    if (!fs.existsSync(soulDir)) {
      log(`Soul directory not found: ${soulDir}`, 'error');
      process.exit(1);
    }

    if (subArgs.includes('--sync')) {
      await syncSymlinks(soulDir, options);
      return;
    }

    if (subArgs.includes('--remove')) {
      await removeSymlinks(soulDir);
      return;
    }

    // Default: show status
    showSymlinkStatus(soulDir);
    return;
  }

  // Parse --dir
  let soulDir = DEFAULT_SOUL_DIR;
  const dirIdx = args.indexOf('--dir');
  if (dirIdx !== -1 && args[dirIdx + 1]) {
    soulDir = path.resolve(args[dirIdx + 1].replace(/^~/, os.homedir()));
  }

  if (args.includes('--update') || args.includes('-u')) {
    await update(soulDir);
  } else {
    await install(soulDir);
  }
}

main().catch(err => {
  console.error();
  log(err.message, 'error');
  process.exit(1);
});
