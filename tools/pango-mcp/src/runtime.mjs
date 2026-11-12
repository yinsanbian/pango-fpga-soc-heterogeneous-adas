import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const MAX_CAPTURE_BYTES = 4 * 1024 * 1024;

function parseEnvFile(file) {
  if (!file) return {};
  const out = {};
  const content = fs.readFileSync(file, 'utf8');
  for (const line of content.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!match) throw new Error(`Invalid environment line in ${file}: ${trimmed.slice(0, 80)}`);
    let value = match[2].trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    out[match[1]] = value;
  }
  return out;
}

export function loadConfiguration(env = process.env) {
  const fromFile = parseEnvFile(env.PANGO_MCP_ENV_FILE);
  const values = { ...fromFile, ...env };
  const defaultConfig = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'pango-mcp.config.json');
  const configFile = env.PANGO_MCP_CONFIG_FILE || defaultConfig;
  if (env.PANGO_MCP_CONFIG_FILE && !fs.existsSync(configFile)) {
    throw new Error('PANGO_MCP_CONFIG_FILE does not exist: ' + configFile);
  }
  const json = fs.existsSync(configFile) ? JSON.parse(fs.readFileSync(configFile, 'utf8')) : {};
  const pdsShell = values.PANGO_MCP_PDS_2025 || values.PANGO_MCP_PDS_SHELL ||
    json.pdsShell || json.pds?.shell || '';
  const modelsimHome = values.PANGO_MCP_MODELSIM_HOME || json.modelsimHome || json.modelsim?.home || '';
  return {
    pdsShell,
    pdsBin: pdsShell ? path.dirname(pdsShell) : '',
    pdsLicense: values.PANGO_LICENSE_FILE || json.pdsLicense || json.pds?.license || '',
    modelsimHome,
    modelsimLicense: values.PANGO_MCP_MODELSIM_LICENSE || json.modelsimLicense || json.modelsim?.license || '',
    stateDir: values.PANGO_MCP_STATE_DIR || json.stateDir || path.join(os.tmpdir(), 'pango-mcp-local'),
    envFile: env.PANGO_MCP_ENV_FILE || '',
    configFile: fs.existsSync(configFile) ? configFile : '',
    boards: json.boards && typeof json.boards === 'object' && !Array.isArray(json.boards) ? json.boards : {},
  };
}

export function requiredString(value, name) {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${name} is required`);
  return value;
}

export function absolutePath(value, name, { kind = 'any', mustExist = true } = {}) {
  const supplied = requiredString(value, name);
  if (!path.isAbsolute(supplied)) throw new Error(`${name} must be an absolute path`);
  const resolved = path.normalize(supplied);
  if (mustExist) {
    if (!fs.existsSync(resolved)) throw new Error(`${name} does not exist: ${resolved}`);
    if (kind === 'file' && !fs.statSync(resolved).isFile()) throw new Error(`${name} is not a file: ${resolved}`);
    if (kind === 'directory' && !fs.statSync(resolved).isDirectory()) throw new Error(`${name} is not a directory: ${resolved}`);
  }
  return resolved;
}

export function findExecutable(name, env = process.env) {
  if (!name) return null;
  if (path.isAbsolute(name)) return fs.existsSync(name) ? name : null;
  const suffixes = process.platform === 'win32' ? ['', '.exe', '.com'] : [''];
  for (const directory of (env.PATH || env.Path || '').split(path.delimiter)) {
    if (!directory) continue;
    for (const suffix of suffixes) {
      const file = path.join(directory, name + suffix);
      if (fs.existsSync(file)) return file;
    }
  }
  return null;
}

function captureTail(chunks, next, state) {
  const buf = Buffer.isBuffer(next) ? next : Buffer.from(next);
  chunks.push(buf);
  state.bytes += buf.length;
  while (state.bytes > MAX_CAPTURE_BYTES && chunks.length > 1) {
    const removed = chunks.shift();
    state.bytes -= removed.length;
    state.truncated = true;
  }
  if (state.bytes > MAX_CAPTURE_BYTES) {
    chunks[0] = chunks[0].subarray(chunks[0].length - MAX_CAPTURE_BYTES);
    state.bytes = chunks[0].length;
    state.truncated = true;
  }
}

export function runProcess(executable, args = [], options = {}) {
  const { cwd = process.cwd(), timeoutSec = 120, env = {}, stdin = null } = options;
  if (!Array.isArray(args) || args.some(arg => typeof arg !== 'string')) {
    throw new Error('Process arguments must be an array of strings');
  }
  const timeoutMs = Math.max(1, Math.min(Number(timeoutSec) || 120, 86400)) * 1000;
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = spawn(executable, args, {
        cwd,
        env: { ...process.env, ...env },
        windowsHide: true,
        shell: false,
        stdio: [stdin === null ? 'ignore' : 'pipe', 'pipe', 'pipe'],
      });
    } catch (error) {
      reject(error);
      return;
    }
    const stdoutChunks = [];
    const stderrChunks = [];
    const stdoutState = { bytes: 0, truncated: false };
    const stderrState = { bytes: 0, truncated: false };
    let timedOut = false;
    child.stdout.on('data', chunk => captureTail(stdoutChunks, chunk, stdoutState));
    child.stderr.on('data', chunk => captureTail(stderrChunks, chunk, stderrState));
    if (stdin !== null) child.stdin.end(stdin);
    const timer = setTimeout(() => {
      timedOut = true;
      if (process.platform === 'win32' && child.pid) {
        const killer = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], {
          stdio: 'ignore', windowsHide: true, shell: false,
        });
        killer.on('error', () => child.kill('SIGKILL'));
      } else {
        child.kill('SIGKILL');
      }
    }, timeoutMs);
    child.on('error', error => {
      clearTimeout(timer);
      reject(error);
    });
    child.on('close', (code, signal) => {
      clearTimeout(timer);
      resolve({
        code,
        signal,
        timedOut,
        stdout: Buffer.concat(stdoutChunks).toString('utf8'),
        stderr: Buffer.concat(stderrChunks).toString('utf8'),
        stdoutTruncated: stdoutState.truncated,
        stderrTruncated: stderrState.truncated,
      });
    });
  });
}

export function compactProcessResult(result, detail = 'summary') {
  const output = `${result.stdout || ''}\n${result.stderr || ''}`.trim();
  return {
    exitCode: result.code,
    timedOut: result.timedOut,
    output: detail === 'full' ? output : output.slice(-16000),
    outputTruncated: !!(result.stdoutTruncated || result.stderrTruncated || output.length > 16000),
  };
}
