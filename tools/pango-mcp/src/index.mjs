import readline from 'node:readline';
import { loadConfiguration, runProcess } from './runtime.mjs';
import { basicTools } from './basic.mjs';
import { pdsTools } from './pds.mjs';
import { modelsimTools } from './modelsim.mjs';
import { retrievalTools } from './retrieval.mjs';
import { hardwareTools } from './hardware.mjs';
import { offlineTools } from './offline.mjs';

const config = loadConfiguration();
const context = { config, runProcess };
const toolList = [
  ...basicTools(context),
  ...pdsTools(context),
  ...modelsimTools(context),
  ...retrievalTools(context),
  ...hardwareTools(context),
  ...offlineTools(context),
];
const toolsByName = new Map(toolList.map(tool => [tool.name, tool]));
if (toolsByName.size !== toolList.length) throw new Error('Duplicate MCP tool name');
context.toolNames = toolList.map(tool => tool.name);
const supportedProtocolVersions = new Set(['2024-11-05', '2025-03-26', '2025-06-18', '2025-11-25']);

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function rpcError(id, code, message) {
  return { jsonrpc: '2.0', id, error: { code, message } };
}

async function handle(request) {
  if (!request || request.jsonrpc !== '2.0' || typeof request.method !== 'string') {
    return rpcError(request?.id ?? null, -32600, 'Invalid JSON-RPC request');
  }
  if (!Object.hasOwn(request, 'id')) return null;
  const { id, method, params = {} } = request;
  switch (method) {
    case 'initialize':
      return { jsonrpc: '2.0', id, result: {
        protocolVersion: supportedProtocolVersions.has(params?.protocolVersion)
          ? params.protocolVersion : '2025-11-25',
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'pango-mcp-local', title: 'Pango MCP (local rebuild)', version: '0.1.0' },
        instructions: 'Use fpga_env before invoking toolchain tools. Device writes are unavailable unless a tool explicitly documents a confirmation gate.',
      } };
    case 'ping':
      return { jsonrpc: '2.0', id, result: {} };
    case 'tools/list':
      return { jsonrpc: '2.0', id, result: { tools: toolList.map(({ name, description, inputSchema, annotations }) => ({
        name, description, inputSchema, ...(annotations ? { annotations } : {}),
      })) } };
    case 'tools/call': {
      const tool = toolsByName.get(params?.name);
      if (!tool) return rpcError(id, -32602, `Unknown tool: ${params?.name}`);
      const args = params?.arguments && typeof params.arguments === 'object' && !Array.isArray(params.arguments)
        ? params.arguments : {};
      try {
        const value = await tool.run(args);
        const structured = value && typeof value === 'object' && !Array.isArray(value)
          ? value : { value };
        return { jsonrpc: '2.0', id, result: {
          content: [{ type: 'text', text: JSON.stringify(structured) }],
          structuredContent: structured,
          isError: structured.ok === false,
        } };
      } catch (error) {
        const body = { ok: false, error: error instanceof Error ? error.message : String(error) };
        return { jsonrpc: '2.0', id, result: {
          content: [{ type: 'text', text: JSON.stringify(body) }],
          structuredContent: body,
          isError: true,
        } };
      }
    }
    default:
      return rpcError(id, -32601, `Method not found: ${method}`);
  }
}

const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on('line', line => {
  if (!line.trim()) return;
  let request;
  try {
    request = JSON.parse(line);
  } catch {
    send(rpcError(null, -32700, 'Invalid JSON'));
    return;
  }
  Promise.resolve(handle(request))
    .then(response => { if (response) send(response); })
    .catch(error => send(rpcError(request?.id ?? null, -32603, String(error))));
});
