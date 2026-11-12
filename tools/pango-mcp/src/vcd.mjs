import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { absolutePath } from './runtime.mjs';

const MAX_VCD_BYTES = 32 * 1024 * 1024;

export function parseVcd(vcdPath) {
  const file = absolutePath(vcdPath, 'vcdPath', { kind: 'file' });
  if (fs.statSync(file).size > MAX_VCD_BYTES) {
    throw new Error('VCD exceeds 32 MiB; filter or export a shorter trace');
  }
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  const scopes = [];
  const signals = [];
  const eventsById = new Map();
  let definitionsDone = false;
  let time = 0;
  let maxTime = 0;
  let timescale = '';
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) continue;
    if (!definitionsDone) {
      let match = line.match(/^\$scope\s+\S+\s+(\S+)/);
      if (match) { scopes.push(match[1]); continue; }
      if (/^\$upscope\b/.test(line)) { scopes.pop(); continue; }
      match = line.match(/^\$var\s+\S+\s+(\d+)\s+(\S+)\s+(\S+)/);
      if (match) {
        const [, width, id, ref] = match;
        signals.push({ id, width: Number(width), ref, name: [...scopes, ref].join('.') });
        if (!eventsById.has(id)) eventsById.set(id, []);
        continue;
      }
      match = line.match(/^\$timescale\s+(.*?)\s*\$end/);
      if (match) { timescale = match[1]; continue; }
      if (line.includes('$enddefinitions')) definitionsDone = true;
      continue;
    }
    if (line.startsWith('#')) {
      const parsed = Number(line.slice(1));
      if (Number.isFinite(parsed)) { time = parsed; maxTime = Math.max(maxTime, time); }
      continue;
    }
    let match = line.match(/^([01xXzZ])(.+)$/);
    if (match) {
      const list = eventsById.get(match[2]);
      if (list) list.push({ time, value: match[1].toLowerCase() });
      continue;
    }
    match = line.match(/^[bBrRsS](\S+)\s+(\S+)$/);
    if (match) {
      const list = eventsById.get(match[2]);
      if (list) list.push({ time, value: match[1].toLowerCase() });
    }
  }
  for (const signal of signals) signal.events = eventsById.get(signal.id) || [];
  return { file, signals, maxTime, timescale };
}

export function findSignal(vcd, name) {
  const exact = vcd.signals.find(s => s.name === name);
  if (exact) return exact;
  const matches = vcd.signals.filter(s => s.ref === name || s.name.endsWith('.' + name));
  if (matches.length === 1) return matches[0];
  if (matches.length > 1) throw new Error('Ambiguous VCD signal: ' + name);
  throw new Error('VCD signal not found: ' + name);
}

function escapeXml(value) {
  return String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
}

function launchFile(file) {
  const command = process.platform === 'win32' ? 'explorer.exe'
    : process.platform === 'darwin' ? 'open' : 'xdg-open';
  const child = spawn(command, [file], { detached: true, stdio: 'ignore', windowsHide: true });
  child.on('error', () => {});
  child.unref();
}

export function renderWave(args) {
  const { vcdPath, signals: requested, maxSignals = 40, width = 1100, inlineSvg = true, open = false } = args;
  const vcd = parseVcd(vcdPath);
  const limit = Math.max(1, Math.min(Number(maxSignals) || 40, 100));
  const selected = Array.isArray(requested) && requested.length
    ? requested.map(name => findSignal(vcd, name))
    : vcd.signals.slice(0, limit);
  const displayed = selected.slice(0, limit);
  const decimatedSignals = [];
  if (!displayed.length) throw new Error('VCD contains no matching signals');
  const chartWidth = Math.max(500, Math.min(Number(width) || 1100, 3000));
  const chartHeight = 80 + displayed.length * 38;
  const x0 = 220;
  const plotWidth = chartWidth - x0 - 24;
  const scale = t => x0 + (vcd.maxTime ? t / vcd.maxTime : 0) * plotWidth;
  const parts = [
    '<svg xmlns="http://www.w3.org/2000/svg" width="' + chartWidth + '" height="' + chartHeight
      + '" viewBox="0 0 ' + chartWidth + ' ' + chartHeight + '">',
    '<rect width="100%" height="100%" fill="#fff"/>',
    '<style>text{font:12px ui-monospace,Consolas,monospace;fill:#243044}.grid{stroke:#e5eaf0}.wave{stroke:#1769aa;stroke-width:2;fill:none}.bus{fill:#eaf2fb;stroke:#1769aa}</style>',
    '<text x="12" y="22">VCD timing diagram' + (vcd.timescale ? ' · ' + escapeXml(vcd.timescale) : '') + '</text>',
  ];
  for (let tick = 0; tick <= 10; tick++) {
    const x = x0 + plotWidth * tick / 10;
    parts.push('<line class="grid" x1="' + x + '" y1="30" x2="' + x + '" y2="' + (chartHeight - 18) + '"/>');
    parts.push('<text x="' + x + '" y="' + (chartHeight - 5) + '" text-anchor="middle">' +
      escapeXml(Math.round(vcd.maxTime * tick / 10)) + '</text>');
  }
  displayed.forEach((signal, index) => {
    const center = 50 + index * 38;
    parts.push('<text x="12" y="' + (center + 4) + '">' + escapeXml(signal.name) + '</text>');
    parts.push('<line class="grid" x1="' + x0 + '" y1="' + (center + 18) + '" x2="' +
      (x0 + plotWidth) + '" y2="' + (center + 18) + '"/>');
    let ev = signal.events;
    if (!ev.length) return;
    if (ev.length > 10000) {
      const stride = Math.ceil(ev.length / 10000);
      ev = ev.filter((_, eventIndex) => eventIndex % stride === 0 || eventIndex === signal.events.length - 1);
      decimatedSignals.push(signal.name);
    }
    if (signal.width === 1) {
      const y = value => value === '1' ? center - 11 : value === '0' ? center + 11 : center;
      let previous = ev[0];
      let pathData = 'M ' + x0 + ' ' + y(previous.value);
      for (let i = 1; i < ev.length; i++) {
        const current = ev[i];
        const x = scale(current.time);
        pathData += ' L ' + x + ' ' + y(previous.value) + ' L ' + x + ' ' + y(current.value);
        previous = current;
      }
      pathData += ' L ' + (x0 + plotWidth) + ' ' + y(previous.value);
      parts.push('<path class="wave" d="' + pathData + '"/>');
    } else {
      for (let i = 0; i < ev.length; i++) {
        const start = scale(ev[i].time);
        const end = i + 1 < ev.length ? scale(ev[i + 1].time) : x0 + plotWidth;
        if (end <= start) continue;
        parts.push('<rect class="bus" x="' + start + '" y="' + (center - 12) + '" width="' +
          (end - start) + '" height="24"/>');
        if (end - start > 34) parts.push('<text x="' + (start + 4) + '" y="' + (center + 4) + '">' +
          escapeXml(ev[i].value) + '</text>');
      }
    }
  });
  parts.push('</svg>');
  const svg = parts.join('');
  const base = vcd.file.toLowerCase().endsWith('.vcd') ? vcd.file.slice(0, -4) : vcd.file;
  const svgPath = base + '.wave.svg';
  const htmlPath = base + '.wave.html';
  fs.writeFileSync(svgPath, svg, 'utf8');
  fs.writeFileSync(htmlPath, '<!doctype html><html><head><meta charset="utf-8"><title>VCD waveform</title></head><body>' +
    svg + '</body></html>', 'utf8');
  if (open) launchFile(htmlPath);
  return {
    ok: true,
    signals: displayed.map(s => s.name),
    decimatedSignals,
    omittedSignals: Math.max(0, selected.length - displayed.length) +
      (requested?.length ? 0 : Math.max(0, vcd.signals.length - limit)),
    artifacts: { waveSvg: svgPath, waveHtml: htmlPath },
    ...(inlineSvg ? { inlineSvg: svg } : {}),
  };
}
