export const DEFAULT_UPSTREAM_URL = "https://api.deepseek.com/anthropic";
export const DEFAULT_MAX_BODY_BYTES = 32 * 1024 * 1024;
export const DEFAULT_UPSTREAM_TIMEOUT_MS = 300_000;

const HOP_BY_HOP_HEADERS = [
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "proxy-connection",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
];

function stripHopByHopHeaders(headers: Headers): void {
  const conn = headers.get("connection");
  if (conn) {
    for (const token of conn.split(",")) {
      const name = token.trim();
      if (name) {
        try {
          headers.delete(name);
        } catch {
          // Ignore invalid header field names in malformed Connection headers.
        }
      }
    }
  }
  for (const h of HOP_BY_HOP_HEADERS) {
    headers.delete(h);
  }
}

export interface ProxyOptions {
  upstreamUrl?: string;
  maxBodyBytes?: number;
  upstreamTimeoutMs?: number;
  log?: (line: string) => void;
  logError?: (line: string) => void;
}

function parsePositiveInt(raw: string | undefined, fallback: number): number {
  if (raw === undefined || raw === "") return fallback;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
}

function sanitizeLogValue(value: string): string {
  return JSON.stringify(value).replace(/\x7f/g, "\\u007f");
}

export function rewriteToolChoice(
  body: string,
  log: (line: string) => void = console.log
): string | null {
  try {
    const json = JSON.parse(body);
    const tc = json?.tool_choice;
    if (tc && typeof tc === "object" && tc.type === "tool" && tc.name) {
      const originalName = String(tc.name);
      json.tool_choice = { type: "any" };
      log(`[rewrite] tool_choice {type:"tool", name:${sanitizeLogValue(originalName)}} → {type:"any"}`);
      return JSON.stringify(json);
    }
    return null;
  } catch {
    return null;
  }
}

async function readBodyWithLimit(
  req: Request,
  maxBodyBytes: number
): Promise<{ body: Buffer | null; tooLarge: boolean }> {
  const rawCl = req.headers.get("content-length");
  if (rawCl !== null) {
    const cl = Number(rawCl);
    if (Number.isFinite(cl) && cl > maxBodyBytes) {
      return { body: null, tooLarge: true };
    }
  }
  if (!req.body) {
    return { body: null, tooLarge: false };
  }
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value) {
        total += value.byteLength;
        if (total > maxBodyBytes) {
          await reader.cancel().catch(() => {});
          return { body: null, tooLarge: true };
        }
        chunks.push(value);
      }
    }
  } finally {
    reader.releaseLock();
  }
  return { body: Buffer.concat(chunks, total), tooLarge: false };
}

export function createProxyHandler(options: ProxyOptions = {}) {
  const upstreamBase = (
    options.upstreamUrl ??
    process.env.UPSTREAM_URL ??
    DEFAULT_UPSTREAM_URL
  ).replace(/\/+$/, "");
  const maxBodyBytes =
    options.maxBodyBytes ??
    parsePositiveInt(process.env.PROXY_MAX_BODY_BYTES, DEFAULT_MAX_BODY_BYTES);
  const upstreamTimeoutMs =
    options.upstreamTimeoutMs ??
    parsePositiveInt(process.env.PROXY_UPSTREAM_TIMEOUT_MS, DEFAULT_UPSTREAM_TIMEOUT_MS);
  const log = options.log ?? console.log;
  const logError = options.logError ?? console.error;

  return async function fetchHandler(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const targetUrl = `${upstreamBase}${url.pathname}${url.search}`;

    const headers = new Headers(req.headers);
    headers.delete("host");
    headers.delete("content-length");
    stripHopByHopHeaders(headers);

    let readResult: { body: Buffer | null; tooLarge: boolean };
    try {
      readResult = await readBodyWithLimit(req, maxBodyBytes);
    } catch (err) {
      if (req.signal?.aborted) {
        return new Response(
          JSON.stringify({ error: { type: "client_closed_request", message: "request aborted" } }),
          { status: 499, headers: { "content-type": "application/json" } }
        );
      }
      const errMsg = err instanceof Error ? err.message : String(err);
      logError(`[proxy] failed to read request body: ${sanitizeLogValue(errMsg)}`);
      return new Response(
        JSON.stringify({ error: { type: "invalid_request_error", message: "failed to read request body" } }),
        { status: 400, headers: { "content-type": "application/json" } }
      );
    }

    if (readResult.tooLarge) {
      return new Response(
        JSON.stringify({ error: { type: "payload_too_large", message: "request body too large" } }),
        { status: 413, headers: { "content-type": "application/json" } }
      );
    }

    let body: BodyInit | undefined = readResult.body ?? undefined;
    const contentEncoding = req.headers.get("content-encoding")?.trim().toLowerCase();
    const isUncompressed = !contentEncoding || contentEncoding === "identity";
    if (readResult.body !== null && isUncompressed) {
      const rewritten = rewriteToolChoice(readResult.body.toString("utf8"), log);
      if (rewritten !== null) {
        body = rewritten;
      }
    }

    log(`[proxy] ${req.method} ${url.pathname} → ${upstreamBase}${url.pathname}`);

    const upstreamController = new AbortController();
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      upstreamController.abort(new DOMException("The operation timed out.", "TimeoutError"));
    }, upstreamTimeoutMs);

    const reqSignal = req.signal;
    let listenerRemoved = false;
    const onReqAbort = () => {
      upstreamController.abort(reqSignal?.reason);
    };
    const cleanupAbortListener = () => {
      if (listenerRemoved) return;
      listenerRemoved = true;
      if (reqSignal) {
        reqSignal.removeEventListener("abort", onReqAbort);
      }
    };
    if (reqSignal) {
      if (reqSignal.aborted) {
        upstreamController.abort(reqSignal.reason);
      } else {
        reqSignal.addEventListener("abort", onReqAbort, { once: true });
      }
    }

    try {
      const resp = await fetch(targetUrl, {
        method: req.method,
        headers,
        body,
        signal: upstreamController.signal,
      });
      clearTimeout(timer);

      if (!resp.ok) {
        log(`[proxy] upstream ${resp.status} ${sanitizeLogValue(resp.statusText)}`);
      }
      const respHeaders = new Headers(resp.headers);
      respHeaders.delete("content-encoding");
      respHeaders.delete("content-length");
      stripHopByHopHeaders(respHeaders);

      if (!resp.body) {
        cleanupAbortListener();
        return new Response(null, {
          status: resp.status,
          statusText: resp.statusText,
          headers: respHeaders,
        });
      }

      const reader = resp.body.getReader();
      const bodyStream = new ReadableStream<Uint8Array>({
        async pull(controller) {
          try {
            const { done, value } = await reader.read();
            if (done) {
              cleanupAbortListener();
              controller.close();
              return;
            }
            controller.enqueue(value);
          } catch (err) {
            cleanupAbortListener();
            controller.error(err);
          }
        },
        async cancel(reason) {
          cleanupAbortListener();
          await reader.cancel(reason).catch(() => {});
        },
      });

      return new Response(bodyStream, {
        status: resp.status,
        statusText: resp.statusText,
        headers: respHeaders,
      });
    } catch (err) {
      clearTimeout(timer);
      cleanupAbortListener();
      if (timedOut && !reqSignal?.aborted) {
        logError(`[proxy] upstream timeout after ${upstreamTimeoutMs}ms`);
        return new Response(
          JSON.stringify({ error: { type: "timeout_error", message: "upstream timeout" } }),
          { status: 504, headers: { "content-type": "application/json" } }
        );
      }
      const errMsg = err instanceof Error ? err.message : String(err);
      logError(`[proxy] upstream unreachable: ${sanitizeLogValue(errMsg)}`);
      return new Response(
        JSON.stringify({ error: { type: "proxy_error", message: "upstream unreachable" } }),
        { status: 502, headers: { "content-type": "application/json" } }
      );
    } finally {
      clearTimeout(timer);
    }
  };
}

if (import.meta.main) {
  const portRaw = process.env.PORT;
  const port = portRaw !== undefined && portRaw !== "" ? Number(portRaw) : 9091;
  const upstreamUrl = (process.env.UPSTREAM_URL ?? DEFAULT_UPSTREAM_URL).replace(/\/+$/, "");
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: Number.isFinite(port) && port >= 0 ? port : 9091,
    fetch: createProxyHandler({ upstreamUrl }),
  });
  console.log(`[proxy] listening on http://localhost:${server.port} → ${upstreamUrl}`);
}
