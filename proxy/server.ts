const TARGET = "https://api.deepseek.com/anthropic";

function rewriteToolChoice(body: string): string | null {
  try {
    const json = JSON.parse(body);
    const tc = json?.tool_choice;
    if (tc && typeof tc === "object" && tc.type === "tool" && tc.name) {
      const originalName = tc.name;
      json.tool_choice = { type: "any" };
      console.log(`[rewrite] tool_choice {type:"tool", name:"${originalName}"} → {type:"any"}`);
      return JSON.stringify(json);
    }
    return null;
  } catch {
    return null;
  }
}

const server = Bun.serve({
  hostname: "127.0.0.1",
  port: 9091,
  async fetch(req) {
    const url = new URL(req.url);
    const targetUrl = `${TARGET}${url.pathname}${url.search}`;

    const headers = new Headers(req.headers);
    headers.delete("host");

    let body: string | null = null;
    if (req.body) {
      body = await req.text();
      const rewritten = rewriteToolChoice(body);
      if (rewritten !== null) body = rewritten;
    }

    console.log(`[proxy] ${req.method} ${url.pathname} → ${targetUrl}`);

    try {
      const proxyReq = new Request(targetUrl, {
        method: req.method,
        headers,
        body,
      });
      const resp = await fetch(proxyReq);
      if (!resp.ok) {
        console.log(`[proxy] upstream ${resp.status} ${resp.statusText}`);
      }
      const respHeaders = new Headers(resp.headers);
      respHeaders.delete("content-encoding");
      respHeaders.delete("content-length");
      return new Response(resp.body, {
        status: resp.status,
        statusText: resp.statusText,
        headers: respHeaders,
      });
    } catch (err) {
      console.error(`[proxy] upstream unreachable: ${err instanceof Error ? err.message : err}`);
      return new Response(
        JSON.stringify({ error: { type: "proxy_error", message: "upstream unreachable" } }),
        { status: 502, headers: { "content-type": "application/json" } }
      );
    }
  },
});

console.log(`[proxy] listening on http://localhost:${server.port} → ${TARGET}`);
