// Reachability probe only: response headers and the first non-empty body
// chunk. This does not verify media segments, keys, decoding, or smooth play.
/**
 * @param {string | URL} url
 * @param {{headers?: HeadersInit, timeoutMs?: number, slowMs?: number,
 * validateFirstChunk?: ((chunk: Uint8Array, status: number) => boolean) | null}} [options]
 * @returns {Promise<{status: "healthy" | "slow" | "failed" | "unknown",
 * latencyMs: number, httpStatus: number, detail: string}>}
 */
export async function probeStreamFirstChunk(url, {
  headers = {}, timeoutMs = 8000, slowMs = 3000, validateFirstChunk = null,
} = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const started = Date.now();
  let reader;
  let response;
  let httpStatus = 0;
  try {
    response = await fetch(url, {
      method: "GET", headers, redirect: "follow", signal: controller.signal,
    });
    httpStatus = response.status;
    if (!response.ok && !(httpStatus >= 300 && httpStatus < 400)) {
      return {
        status: [401, 403, 405, 429].includes(httpStatus) ? "unknown" : "failed",
        latencyMs: Date.now() - started, httpStatus, detail: `HTTP ${httpStatus}`,
      };
    }
    reader = response.body?.getReader();
    if (!reader) throw new Error("Response body is empty.");
    let chunk;
    do {
      chunk = await reader.read();
      if (chunk.done) throw new Error("Response body is empty.");
    } while (!chunk.value?.byteLength);
    if (validateFirstChunk && !validateFirstChunk(chunk.value, httpStatus)) {
      throw new Error("Response body is not a valid stream manifest.");
    }
    const latencyMs = Date.now() - started;
    return {
      status: latencyMs > slowMs ? "slow" : "healthy", latencyMs, httpStatus,
      detail: "Upstream headers and first body chunk reachable; playback not verified.",
    };
  } catch (error) {
    return {
      status: "failed", latencyMs: Date.now() - started, httpStatus,
      detail: controller.signal.aborted ? "First body chunk timed out."
        : error instanceof Error ? error.message : String(error),
    };
  } finally {
    clearTimeout(timer);
    // Health checks consume only a small prefix, never leave media downloads
    // running after reporting a result. Abort also unblocks a stalled reader.
    controller.abort();
    if (reader) await reader.cancel().catch(() => {});
    else await response?.body?.cancel().catch(() => {});
  }
}
