import fs from 'node:fs';
import path from 'node:path';

// These indexes are built from the user's PDS installation. No vendor text or
// precomputed corpus is shipped with this server.
const primitiveIndexes = new Map();
const ipIndexes = new Map();
const documentIndexes = new Map();

function pdsRoot(config) {
  const bin = config?.pdsBin || (config?.pdsShell ? path.dirname(config.pdsShell) : '');
  if (!bin || !path.isAbsolute(bin)) throw new Error('PDS is not configured: set PANGO_MCP_PDS_2025 to pds_shell.exe');
  const root = path.resolve(bin, '..');
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) throw new Error(`PDS install directory is unavailable: ${root}`);
  return root;
}

function boundedInt(value, fallback, maximum) {
  if (value === undefined || value === null || value === '') return fallback;
  const number = Number(value);
  if (!Number.isInteger(number) || number < 1) throw new Error('limit must be a positive integer');
  return Math.min(number, maximum);
}

function keywordMode(mode) {
  if (mode !== undefined && !['auto', 'keyword', 'semantic'].includes(mode)) {
    throw new Error('mode must be auto, keyword, or semantic');
  }
  return 'keyword';
}

function terms(query) {
  return String(query || '').toLowerCase().match(/[\p{L}\p{N}_]+/gu)?.slice(0, 12) || [];
}

function score(text, words) {
  if (!words.length) return 0;
  const value = String(text || '').toLowerCase();
  let result = 0;
  for (const word of words) {
    if (!value.includes(word)) return 0;
    result += value.startsWith(word) ? 5 : 2;
  }
  return result;
}

function walkFiles(root, accept, { maxEntries = 15000, maxDepth = 12 } = {}) {
  if (!fs.existsSync(root)) return [];
  const found = [];
  const stack = [{ dir: root, depth: 0 }];
  let entriesSeen = 0;
  while (stack.length) {
    const { dir, depth } = stack.pop();
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
    catch { continue; }
    for (const entry of entries) {
      if (++entriesSeen > maxEntries) return found;
      const file = path.join(dir, entry.name);
      if (entry.isDirectory() && depth < maxDepth) stack.push({ dir: file, depth: depth + 1 });
      else if (entry.isFile() && accept(entry.name)) found.push(file);
    }
  }
  return found.sort((a, b) => a.localeCompare(b));
}

function primitiveCategory(name) {
  const n = name.toUpperCase();
  if (/PLL|CLK|OSC/.test(n)) return 'clock_pll';
  if (/DFF|LATCH|FF_/.test(n)) return 'ff_latch';
  if (/LUT|MUX/.test(n)) return 'lut';
  if (/RAM|ROM|DRM|FIFO|BRAM/.test(n)) return 'mem';
  if (/SERDES|DDR|IDDR|ODDR|LVDS/.test(n)) return 'serdes_ddr';
  if (/MIPI/.test(n)) return 'mipi';
  if (/PCIE/.test(n)) return 'pcie';
  if (/ADC|DAC|TEMP/.test(n)) return 'analog';
  if (/IBUF|OBUF|IOBUF|_IO|_BUF|^GTP_BUF/.test(n)) return 'io_buffer';
  return 'config_misc';
}

function parsePrimitives(file) {
  const source = fs.readFileSync(file, 'utf8');
  const modules = [];
  const pattern = /^\s*module\s+(GTP_[A-Za-z0-9_]+)\b([\s\S]*?)^\s*endmodule\b/gm;
  let match;
  while ((match = pattern.exec(source))) {
    const header = match[2].split(';', 1)[0]
      .replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ');
    const parameters = [];
    const parameterPattern = /\bparameter\s+(?:(?:signed|integer|real|reg|logic|wire)\s+)?(?:\[[^\]]+\]\s*)?([A-Za-z_]\w*)\s*=\s*([^,\n)]+)/g;
    let parameter;
    while ((parameter = parameterPattern.exec(header))) {
      parameters.push({ name: parameter[1], default: parameter[2].trim() });
    }
    const ports = [];
    const portPattern = /\b(input|output|inout)\s+(?:(?:wire|reg|logic)\s+)?(\[[^\]]+\]\s*)?([A-Za-z_]\w*)/g;
    let port;
    while ((port = portPattern.exec(header))) {
      ports.push({ direction: port[1], name: port[3], ...(port[2] ? { width: port[2].trim() } : {}) });
    }
    modules.push({ name: match[1], category: primitiveCategory(match[1]), parameters, ports, sourcePath: file });
  }
  return modules;
}

function primitiveIndex(root) {
  if (primitiveIndexes.has(root)) return primitiveIndexes.get(root);
  const file = path.join(root, 'arch', 'vendor', 'pango', 'logos2', 'common', 'lib', 'gtp_lib.v');
  if (!fs.existsSync(file)) throw new Error(`Logos2 primitive library was not found: ${file}`);
  const modules = parsePrimitives(file);
  primitiveIndexes.set(root, modules);
  return modules;
}

function xmlText(block, tag) {
  const match = block.match(new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${tag}>`, 'i'));
  if (!match) return '';
  return match[1].replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/<[^>]*>/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").trim();
}

function xmlSection(block, tag) {
  return block.match(new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${tag}>`, 'i'))?.[1] || '';
}

function attrNames(block, tag) {
  return [...block.matchAll(new RegExp(`<${tag}\\b[^>]*\\bname\\s*=\\s*["']([^"']+)["']`, 'gi'))].map(m => m[1]);
}

function parseIp(file, root) {
  let xml;
  try { xml = fs.readFileSync(file, 'utf8'); }
  catch { return null; }
  if (!/<ip_index\b/i.test(xml)) return null;
  xml = xml.replace(/<!--[\s\S]*?-->/g, '');
  const header = xmlSection(xml, 'header');
  const supported = xmlSection(xml, 'supported');
  const paramList = xmlSection(xml, 'param_list');
  const dir = path.dirname(file);
  const dataRel = xmlText(header, 'datasheet');
  const dataPath = dataRel ? path.resolve(dir, dataRel) : '';
  const safeDataPath = dataPath && dataPath.toLowerCase().startsWith(root.toLowerCase() + path.sep) && fs.existsSync(dataPath)
    ? dataPath : null;
  const params = [];
  for (const match of paramList.matchAll(/<param(?:\s[^>]*)?>([\s\S]*?)<\/param>/gi)) {
    const body = match[1];
    const name = xmlText(body, 'name');
    if (!name) continue;
    params.push({
      name,
      type: xmlText(body, 'type') || null,
      default: xmlText(body, 'default') || null,
      ...(xmlText(body, 'min') ? { min: xmlText(body, 'min') } : {}),
      ...(xmlText(body, 'max') ? { max: xmlText(body, 'max') } : {}),
      ...(Array.from(body.matchAll(/<item(?:\s[^>]*)?>([\s\S]*?)<\/item>/gi), m => m[1].trim()).length
        ? { options: Array.from(body.matchAll(/<item(?:\s[^>]*)?>([\s\S]*?)<\/item>/gi), m => m[1].trim()).slice(0, 100) } : {}),
    });
  }
  return {
    slug: path.basename(dir), name: xmlText(header, 'name') || xmlText(header, 'display_name') || path.basename(dir),
    displayName: xmlText(header, 'display_name') || null,
    category: xmlText(header, 'category') || null,
    version: xmlText(header, 'version') || null,
    topModule: xmlText(header, 'top_module') || null,
    families: attrNames(supported, 'family'),
    deviceSeries: attrNames(supported, 'device_series'),
    devices: attrNames(supported, 'device'),
    datasheetPath: safeDataPath,
    sourcePath: file,
    parameters: params,
  };
}

function ipIndex(root) {
  if (ipIndexes.has(root)) return ipIndexes.get(root);
  const dir = path.join(root, 'ip');
  const result = walkFiles(dir, n => n.toLowerCase() === 'index.xml').map(f => parseIp(f, root)).filter(Boolean);
  ipIndexes.set(root, result);
  return result;
}

function cleanHtml(content) {
  return content.replace(/<(?:script|style)\b[^>]*>[\s\S]*?<\/(?:script|style)>/gi, ' ')
    .replace(/<[^>]+>/g, ' ').replace(/&nbsp;/gi, ' ').replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<').replace(/&gt;/gi, '>').replace(/\s+/g, ' ').trim();
}

function documentIndex(root) {
  if (documentIndexes.has(root)) return documentIndexes.get(root);
  const manuals = walkFiles(path.join(root, 'doc'), n => /\.pdf$/i.test(n), { maxDepth: 3 });
  const datasheets = walkFiles(path.join(root, 'ip'), n => /\.pdf$/i.test(n));
  const textFiles = walkFiles(path.join(root, 'ip'), n => /\.(?:html|txt|md)$/i.test(n));
  documentIndexes.set(root, { manuals, datasheets, textFiles });
  return { manuals, datasheets, textFiles };
}

function pdfMatches(files, words, limit) {
  const ranked = files.map(file => ({ path: file, title: path.basename(file, '.pdf').replace(/[_-]+/g, ' '),
    score: words.length ? score(file, words) : 1 }))
    .filter(item => item.score > 0).sort((a, b) => b.score - a.score || a.path.localeCompare(b.path));
  return ranked.slice(0, limit).map(({ score: _score, ...item }) => item);
}

function textMatches(files, words, limit) {
  if (!words.length) return [];
  const result = [];
  for (const file of files) {
    let stat;
    try { stat = fs.statSync(file); } catch { continue; }
    if (stat.size > 1024 * 1024) continue;
    let content;
    try { content = cleanHtml(fs.readFileSync(file, 'utf8')); } catch { continue; }
    const lower = content.toLowerCase();
    const positions = words.map(word => lower.indexOf(word));
    if (positions.some(pos => pos < 0)) continue;
    const first = Math.min(...positions);
    const start = Math.max(0, first - 130);
    result.push({ path: file, snippet: content.slice(start, start + 600), score: score(file, words) + words.length * 2 });
  }
  return result.sort((a, b) => b.score - a.score || a.path.localeCompare(b.path))
    .slice(0, limit).map(({ score: _score, ...item }) => item);
}

export function retrievalTools(ctx) {
  return [
    {
      name: 'fpga_primitive_lookup',
      description: 'Search the installed PDS Logos2 GTP primitive library. Exact names return ports, parameters, an instantiation template, and the source path.',
      inputSchema: { type: 'object', properties: {
        mode: { type: 'string', enum: ['auto', 'keyword', 'semantic'] },
        name: { type: 'string' }, limit: { type: 'integer', minimum: 1, maximum: 50 },
        query: { type: 'string' }, category: { type: 'string' },
      } },
      run(args) {
        const root = pdsRoot(ctx.config);
        const modules = primitiveIndex(root);
        const limit = boundedInt(args.limit, 10, 50);
        const modeUsed = keywordMode(args.mode);
        if (args.name) {
          const item = modules.find(m => m.name.toLowerCase() === String(args.name).toLowerCase());
          if (!item) return { ok: false, error: `Primitive not found: ${args.name}`, suggestions: modules.filter(m => m.name.toLowerCase().includes(String(args.name).toLowerCase())).slice(0, limit).map(m => m.name) };
          const template = `${item.name} u_${item.name.toLowerCase()} (\n${item.ports.map(p => `  .${p.name}()` ).join(',\n')}\n);`;
          return { ok: true, modeUsed, ...item, template };
        }
        let items = modules;
        if (args.category) items = items.filter(m => m.category === args.category);
        const words = terms(args.query);
        if (words.length) items = items.map(item => ({ item, rank: score(`${item.name} ${item.category} ${item.ports.map(p => p.name).join(' ')}`, words) }))
          .filter(x => x.rank > 0).sort((a, b) => b.rank - a.rank).map(x => x.item);
        const categories = Object.fromEntries([...new Set(modules.map(m => m.category))].sort().map(category => [category, modules.filter(m => m.category === category).length]));
        return { ok: true, modeUsed, sourcePath: modules[0]?.sourcePath || null, total: items.length, categories,
          results: items.slice(0, limit).map(({ name, category, ports, parameters }) => ({ name, category, portCount: ports.length, parameterCount: parameters.length })) };
      },
    },
    {
      name: 'fpga_ip_lookup',
      description: 'Search IP metadata parsed from index.xml files in the installed PDS IP directory. Exact slug lookup includes parameters, supported devices, and the local datasheet path.',
      inputSchema: { type: 'object', properties: {
        mode: { type: 'string', enum: ['auto', 'keyword', 'semantic'] }, slug: { type: 'string' },
        limit: { type: 'integer', minimum: 1, maximum: 50 }, query: { type: 'string' },
        category: { type: 'string' }, maxParams: { type: 'integer', minimum: 1, maximum: 200 },
      } },
      run(args) {
        const root = pdsRoot(ctx.config);
        const ips = ipIndex(root);
        const limit = boundedInt(args.limit, 10, 50);
        const modeUsed = keywordMode(args.mode);
        if (args.slug) {
          const matches = ips.filter(ip => ip.slug.toLowerCase() === String(args.slug).toLowerCase());
          if (!matches.length) return { ok: false, error: `IP slug not found: ${args.slug}`, suggestions: ips.filter(ip => ip.slug.toLowerCase().includes(String(args.slug).toLowerCase())).slice(0, limit).map(ip => ip.slug) };
          const maxParams = boundedInt(args.maxParams, 60, 200);
          return { ok: true, modeUsed, results: matches.map(ip => ({ ...ip, parameterCount: ip.parameters.length,
            parameters: ip.parameters.slice(0, maxParams) })) };
        }
        let selected = ips;
        if (args.category) selected = selected.filter(ip => (ip.category || '').toLowerCase().includes(String(args.category).toLowerCase()));
        const words = terms(args.query);
        if (words.length) selected = selected.map(ip => ({ ip, rank: score(`${ip.slug} ${ip.name} ${ip.displayName} ${ip.category} ${ip.topModule}`, words) }))
          .filter(x => x.rank > 0).sort((a, b) => b.rank - a.rank).map(x => x.ip);
        return { ok: true, modeUsed, total: selected.length,
          results: selected.slice(0, limit).map(({ slug, name, displayName, category, version, datasheetPath, sourcePath }) =>
            ({ slug, name, displayName, category, version, datasheetPath, sourcePath })) };
      },
    },
    {
      name: 'fpga_doc_search',
      description: 'Find installed PDS manual and IP datasheet PDF paths, plus matching snippets from installed IP text pages. Uses bounded keyword search; no external corpus or embedding service.',
      inputSchema: { type: 'object', properties: {
        kind: { type: 'string', enum: ['all', 'chunk', 'manual', 'datasheet'] },
        mode: { type: 'string', enum: ['auto', 'keyword', 'semantic'] },
        limit: { type: 'integer', minimum: 1, maximum: 30 }, query: { type: 'string' },
      } },
      run(args) {
        const root = pdsRoot(ctx.config);
        const docs = documentIndex(root);
        const kind = args.kind || 'all';
        if (!['all', 'chunk', 'manual', 'datasheet'].includes(kind)) throw new Error('kind must be all, chunk, manual, or datasheet');
        const limit = boundedInt(args.limit, 8, 30);
        const words = terms(args.query);
        const out = { ok: true, modeUsed: keywordMode(args.mode), query: args.query || '',
          inventory: { manuals: docs.manuals.length, datasheets: docs.datasheets.length, textPages: docs.textFiles.length } };
        if (kind === 'all' || kind === 'manual') out.manuals = pdfMatches(docs.manuals, words, limit);
        if (kind === 'all' || kind === 'datasheet') out.datasheets = pdfMatches(docs.datasheets, words, limit);
        if (kind === 'all' || kind === 'chunk') out.chunks = textMatches(docs.textFiles, words, limit);
        if (kind === 'chunk' && !out.chunks.length) out.note = 'No matching installed text page. PDF paths are available with kind=manual or kind=datasheet.';
        return out;
      },
    },
  ];
}
