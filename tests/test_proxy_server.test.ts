import { describe, expect, test, afterEach } from "bun:test";
import { createProxyHandler, rewriteToolChoice } from "../proxy/server.ts";

let servers: ReturnType<typeof Bun.serve>[] = [];

afterEach(() => {
  for (const s of servers) {
    s.stop(true);
  }
  servers = [];
});

function startMockUpstream(
  handler: (req: Request) => Response | Promise<Response>
): { url: string; server: ReturnType<typeof Bun.serve> } {
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch: handler,
  });
  servers.push(server);
  return { url: `http://127.0.0.1:${server.port}`, server };
}

function startProxy(opts: {
  upstreamUrl: string;
  maxBodyBytes?: number;
  upstreamTimeoutMs?: number;
  log?: (line: string) => void;
  logError?: (line: string) => void;
}): { url: string; server: ReturnType<typeof Bun.serve> } {
  const fetchHandler = createProxyHandler({
    upstreamUrl: opts.upstreamUrl,
    maxBodyBytes: opts.maxBodyBytes,
    upstreamTimeoutMs: opts.upstreamTimeoutMs,
    log: opts.log,
    logError: opts.logError,
  });
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch: fetchHandler,
  });
  servers.push(server);
  return { url: `http://127.0.0.1:${server.port}`, server };
}

describe("proxy/server.ts", () => {
  test("rewriteToolChoice rewrites type=tool and preserves valid/malformed bodies", () => {
    const rewritten = rewriteToolChoice(
      JSON.stringify({ model: "deepseek-v4-pro", tool_choice: { type: "tool", name: "ping" } })
    );
    expect(rewritten).not.toBeNull();
    expect(JSON.parse(rewritten!).tool_choice).toEqual({ type: "any" });
    expect(rewriteToolChoice(JSON.stringify({ tool_choice: { type: "auto" } }))).toBeNull();
    expect(rewriteToolChoice("{malformed json")).toBeNull();
  });

  test("strips stale request content-length/transfer-encoding/connection and response hop-by-hop headers", async () => {
    let seenHeaders: Record<string, string> = {};
    let seenBody = "";
    const upstream = startMockUpstream(async (req) => {
      seenHeaders = Object.fromEntries(req.headers.entries());
      seenBody = await req.text();
      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: {
          "content-type": "application/json",
          connection: "keep-alive",
          "transfer-encoding": "chunked",
          "x-upstream": "yes",
        },
      });
    });

    const proxy = startProxy({ upstreamUrl: upstream.url });
    const payload = JSON.stringify({
      model: "deepseek-v4-pro",
      tool_choice: { type: "tool", name: "a_very_long_tool_name_that_will_shrink_when_rewritten" },
    });

    const resp = await fetch(`${proxy.url}/v1/messages`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "content-length": String(payload.length + 50),
        connection: "close",
        "proxy-connection": "keep-alive",
        te: "trailers",
      },
      body: payload,
    });

    expect(resp.status).toBe(200);
    const json = await resp.json();
    expect(json).toEqual({ ok: true });
    expect(JSON.parse(seenBody).tool_choice).toEqual({ type: "any" });
    expect(seenHeaders["content-length"]).toBe(String(Buffer.byteLength(seenBody)));
    expect(seenHeaders["transfer-encoding"]).toBeUndefined();
    expect(seenHeaders["proxy-connection"]).toBeUndefined();
    expect(seenHeaders["te"]).toBeUndefined();
    // Client sent "close"; proxy deleted it so Bun fetch uses its own transport connection header, not client's "close"
    expect(seenHeaders["connection"]).not.toBe("close");
    expect(resp.headers.get("x-upstream")).toBe("yes");
    expect(resp.headers.get("transfer-encoding")).toBeNull();
  });

  test("passes through malformed JSON body unchanged without crashing", async () => {
    let seenBody = "";
    const upstream = startMockUpstream(async (req) => {
      seenBody = await req.text();
      return new Response("ok", { status: 200 });
    });
    const proxy = startProxy({ upstreamUrl: upstream.url });
    const resp = await fetch(`${proxy.url}/v1/messages`, {
      method: "POST",
      body: "{not valid json",
    });
    expect(resp.status).toBe(200);
    expect(seenBody).toBe("{not valid json");
  });

  test("returns 413 when request body exceeds maxBodyBytes", async () => {
    let hitUpstream = false;
    const upstream = startMockUpstream(() => {
      hitUpstream = true;
      return new Response("ok");
    });
    const proxy = startProxy({ upstreamUrl: upstream.url, maxBodyBytes: 64 });
    const bigBody = JSON.stringify({ data: "x".repeat(200) });
    const resp = await fetch(`${proxy.url}/v1/messages`, {
      method: "POST",
      body: bigBody,
    });
    expect(resp.status).toBe(413);
    expect(hitUpstream).toBe(false);
  });

  test("returns 504 on upstream timeout and 502 on connection failure", async () => {
    const slowUpstream = startMockUpstream(async () => {
      await Bun.sleep(300);
      return new Response("too late");
    });
    const proxyTimeout = startProxy({ upstreamUrl: slowUpstream.url, upstreamTimeoutMs: 50 });
    const resp504 = await fetch(`${proxyTimeout.url}/v1/messages`, {
      method: "POST",
      body: "{}",
    });
    expect(resp504.status).toBe(504);

    // Dead upstream -> 502
    const dead = startMockUpstream(() => new Response("x"));
    const deadUrl = dead.url;
    dead.server.stop(true);
    const proxyDead = startProxy({ upstreamUrl: deadUrl, upstreamTimeoutMs: 1000 });
    const resp502 = await fetch(`${proxyDead.url}/v1/messages`, {
      method: "POST",
      body: "{}",
    });
    expect(resp502.status).toBe(502);
  });

  test("sanitizes logs: omits url.search and escapes control chars/newlines in tc.name", async () => {
    const logs: string[] = [];
    let seenSearch = "";
    const upstream = startMockUpstream((req) => {
      seenSearch = new URL(req.url).search;
      return new Response("{}", { status: 200 });
    });
    const proxy = startProxy({
      upstreamUrl: upstream.url,
      log: (line) => logs.push(line),
    });

    const resp = await fetch(`${proxy.url}/v1/messages?api_key=SECRET-QUERY-CANARY`, {
      method: "POST",
      body: JSON.stringify({
        tool_choice: { type: "tool", name: "evil\n[FAKE] log\r\x1b[31m" },
      }),
    });
    expect(resp.status).toBe(200);
    expect(seenSearch).toBe("?api_key=SECRET-QUERY-CANARY");
    const combined = logs.join("\n");
    expect(combined).not.toContain("SECRET-QUERY-CANARY");
    expect(logs.some((entry) => entry.startsWith("[FAKE]"))).toBe(false);
    // Every log entry must be a single line with control characters escaped
    for (const entry of logs) {
      expect(entry).not.toMatch(/[\x00-\x1f\x7f]/);
    }
  });

  test("propagates client abort to upstream and supports PORT/UPSTREAM_URL env in standalone server", async () => {
    let upstreamAborted = false;
    const upstream = startMockUpstream(async (req) => {
      req.signal.addEventListener("abort", () => {
        upstreamAborted = true;
      });
      await Bun.sleep(1000);
      return new Response("ok");
    });

    const proc = Bun.spawn(["bun", "run", new URL("../proxy/server.ts", import.meta.url).pathname], {
      env: {
        ...process.env,
        PORT: "0",
        UPSTREAM_URL: upstream.url,
        PROXY_UPSTREAM_TIMEOUT_MS: "5000",
        PROXY_MAX_BODY_BYTES: "1024",
      },
      stdout: "pipe",
      stderr: "pipe",
    });

    try {
      // Read listening line from stdout to discover ephemeral port
      const reader = proc.stdout.getReader();
      const decoder = new TextDecoder();
      let buf = "";
      let port = 0;
      const deadline = Date.now() + 5000;
      while (Date.now() < deadline) {
        const { value, done } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        const m = buf.match(/http:\/\/(?:localhost|127\.0\.0\.1):(\d+)/);
        if (m) {
          port = Number(m[1]);
          break;
        }
      }
      reader.releaseLock();
      expect(port).toBeGreaterThan(0);

      const ac = new AbortController();
      setTimeout(() => ac.abort(), 50);
      await expect(
        fetch(`http://127.0.0.1:${port}/v1/messages`, {
          method: "POST",
          body: "{}",
          signal: ac.signal,
        })
      ).rejects.toThrow();

      await Bun.sleep(100);
      expect(upstreamAborted).toBe(true);
    } finally {
      proc.kill();
      await proc.exited;
    }
  });

  test("does not abort long SSE stream after response headers arrive within upstreamTimeoutMs", async () => {
    const logErrors: string[] = [];
    const upstream = startMockUpstream(async () => {
      await Bun.sleep(10);
      const stream = new ReadableStream<Uint8Array>({
        async start(controller) {
          const enc = new TextEncoder();
          controller.enqueue(enc.encode("data: chunk1\n\n"));
          await Bun.sleep(220);
          controller.enqueue(enc.encode("data: chunk2\n\n"));
          controller.close();
        },
      });
      return new Response(stream, {
        status: 200,
        headers: { "content-type": "text/event-stream" },
      });
    });

    const proxy = startProxy({
      upstreamUrl: upstream.url,
      upstreamTimeoutMs: 120,
      logError: (line) => logErrors.push(line),
    });

    const resp = await fetch(`${proxy.url}/v1/messages`, {
      method: "POST",
      body: JSON.stringify({ stream: true }),
    });
    expect(resp.status).toBe(200);
    const text = await resp.text();
    expect(text).toBe("data: chunk1\n\ndata: chunk2\n\n");
    expect(logErrors).toEqual([]);
  });

  test("returns 413 for chunked body without Content-Length exceeding maxBodyBytes", async () => {
    let hitUpstream = false;
    const upstream = startMockUpstream(() => {
      hitUpstream = true;
      return new Response("ok");
    });
    const proxy = startProxy({ upstreamUrl: upstream.url, maxBodyBytes: 64 });
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        const enc = new TextEncoder();
        controller.enqueue(enc.encode("a".repeat(40)));
        controller.enqueue(enc.encode("b".repeat(40)));
        controller.close();
      },
    });
    const resp = await fetch(`${proxy.url}/v1/messages`, {
      method: "POST",
      body: stream,
    });
    expect(resp.status).toBe(413);
    expect(hitUpstream).toBe(false);
  });

  test("forwards gzip and arbitrary binary request bodies losslessly without UTF-8 corruption", async () => {
    let seenBytes = new Uint8Array();
    let seenEncoding: string | null = null;
    const upstream = startMockUpstream(async (req) => {
      seenEncoding = req.headers.get("content-encoding");
      seenBytes = new Uint8Array(await req.arrayBuffer());
      return new Response("ok", { status: 200 });
    });
    const proxy = startProxy({ upstreamUrl: upstream.url });

    // Valid gzip bytes plus arbitrary raw invalid-UTF-8 bytes
    const rawGzip = Bun.gzipSync(
      Buffer.from(JSON.stringify({ tool_choice: { type: "tool", name: "keep_me_compressed" } }))
    );
    const respGzip = await fetch(`${proxy.url}/v1/messages`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "content-encoding": "gzip",
      },
      body: rawGzip,
    });
    expect(respGzip.status).toBe(200);
    expect(seenEncoding).toBe("gzip");
    expect(Buffer.from(seenBytes).equals(Buffer.from(rawGzip))).toBe(true);

    // Uncompressed binary payload (non-UTF8 bytes, not valid JSON) must also pass through untouched
    const rawBinary = new Uint8Array([0xff, 0xfe, 0x80, 0x00, 0x41]);
    const respBin = await fetch(`${proxy.url}/v1/messages`, {
      method: "POST",
      headers: { "content-type": "application/octet-stream" },
      body: rawBinary,
    });
    expect(respBin.status).toBe(200);
    expect(Buffer.from(seenBytes).equals(Buffer.from(rawBinary))).toBe(true);
  });

  test("strips headers named in Connection header and proxy-authenticate/proxy-authorization", async () => {
    let seenHeaders: Record<string, string> = {};
    const upstream = startMockUpstream((req) => {
      seenHeaders = Object.fromEntries(req.headers.entries());
      return new Response("ok", {
        status: 200,
        headers: {
          connection: "x-resp-hop",
          "x-resp-hop": "secret-hop",
          "proxy-authenticate": "Basic",
          "x-keep": "1",
        },
      });
    });
    const proxy = startProxy({ upstreamUrl: upstream.url });
    const resp = await fetch(`${proxy.url}/v1/messages`, {
      method: "POST",
      headers: {
        connection: "x-hop-custom, x-hop-second",
        "x-hop-custom": "drop-me",
        "x-hop-second": "drop-me-too",
        "proxy-authorization": "Basic dXNlcjpwYXNz",
        "x-end-to-end": "keep-me",
      },
      body: "{}",
    });
    expect(resp.status).toBe(200);
    expect(seenHeaders["x-hop-custom"]).toBeUndefined();
    expect(seenHeaders["x-hop-second"]).toBeUndefined();
    expect(seenHeaders["proxy-authorization"]).toBeUndefined();
    expect(seenHeaders["x-end-to-end"]).toBe("keep-me");
    expect(resp.headers.get("x-resp-hop")).toBeNull();
    expect(resp.headers.get("proxy-authenticate")).toBeNull();
    expect(resp.headers.get("x-keep")).toBe("1");
  });

  test("returns 400 when request body stream errors mid-read and sanitizes resp.statusText/err.message", async () => {
    const logs: string[] = [];
    const logErrors: string[] = [];
    const upstream = startMockUpstream(() => {
      return new Response("err", {
        status: 500,
        statusText: "Bad\n[FAKE]\r\x1b[31m",
      });
    });
    const proxy = startProxy({
      upstreamUrl: upstream.url,
      log: (line) => logs.push(line),
      logError: (line) => logErrors.push(line),
    });

    const respStatus = await fetch(`${proxy.url}/v1/messages`, { method: "POST", body: "{}" });
    expect(respStatus.status).toBe(500);
    for (const entry of logs) {
      expect(entry).not.toMatch(/[\x00-\x1f\x7f]/);
    }

    const fetchHandler = createProxyHandler({
      upstreamUrl: upstream.url,
      log: (line) => logs.push(line),
      logError: (line) => logErrors.push(line),
    });
    const failingStream = new ReadableStream<Uint8Array>({
      pull() {
        throw new Error("stream\nbreak\r\x1b[31m");
      },
    });
    const respReadErr = await fetchHandler(
      new Request("http://127.0.0.1/v1/messages", { method: "POST", body: failingStream })
    );
    expect(respReadErr.status).toBe(400);
    expect(logErrors.length).toBeGreaterThan(0);
    for (const entry of logErrors) {
      expect(entry).not.toMatch(/[\x00-\x1f\x7f]/);
    }
  });
});
