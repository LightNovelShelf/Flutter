/// 临时性能采集器：连 Dart VM Service，滚动拉 timeline + CPU 采样。
/// 用法: bun tool/perf_collect.ts <vmServiceHttpUri> [outDir]

import { appendFileSync } from "node:fs";

type TraceEvent = {
	readonly ph?: string;
	readonly name?: string;
	readonly tid?: number;
	readonly ts?: number;
	readonly dur?: number;
	readonly args?: { readonly name?: string };
};

type Isolate = { readonly id: string; readonly name?: string };

type CpuFunction = {
	readonly function?: {
		readonly name?: string;
		readonly owner?: { readonly name?: string };
	};
};

type CpuSample = { readonly stack?: readonly number[]; readonly timestamp?: number };

type RpcResult = {
	readonly isolates?: readonly Isolate[];
	readonly traceEvents?: readonly TraceEvent[];
	readonly functions?: readonly CpuFunction[];
	readonly samples?: readonly CpuSample[];
	readonly error?: unknown;
};

type Span = { readonly name: string; readonly tid: number; readonly ts: number; readonly dur: number };

const UI_FRAME = "Animator::BeginFrame";
const RASTER_FRAME = "Rasterizer::DoDraw";
const WINDOW_US = 10_000_000;

const httpUri = process.argv[2];
const outDir = process.argv[3] ?? "/tmp/perf90";
if (!httpUri) throw new Error("need vm service uri");

const wsUri = `${httpUri.replace(/^http/, "ws").replace(/\/$/, "")}/ws`;
await Bun.$`mkdir -p ${outDir}`.quiet();

const ws = new WebSocket(wsUri);
let seq = 0;
const pending = new Map<string, (value: RpcResult) => void>();

ws.addEventListener("message", (ev: MessageEvent) => {
	// VM Service JSON-RPC 响应；结构由协议保证，仅在此边界断言一次。
	const msg = JSON.parse(String(ev.data)) as { id?: string; result?: RpcResult; error?: unknown };
	const resolve = msg.id ? pending.get(msg.id) : undefined;
	if (!msg.id || !resolve) return;
	pending.delete(msg.id);
	resolve(msg.error ? { error: msg.error } : (msg.result ?? {}));
});

function call(method: string, params: Record<string, unknown> = {}): Promise<RpcResult> {
	const id = String(++seq);
	const { promise, resolve } = Promise.withResolvers<RpcResult>();
	pending.set(id, resolve);
	ws.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }));
	return promise;
}

{
	const { promise, resolve } = Promise.withResolvers<void>();
	ws.addEventListener("open", () => resolve());
	await promise;
}
console.log("connected", wsUri);

const vm = await call("getVM");
const isolates = vm.isolates ?? [];
const uiIsolate = isolates.find((i) => i.name?.includes("main")) ?? isolates[0];
console.log("isolates:", isolates.map((i) => `${i.id}:${i.name}`).join(", "));

await call("setVMTimelineFlags", { recordedStreams: ["Dart", "Embedder", "GC", "API"] });

// 逐 widget/RenderObject 的 timeline 事件，不开的话只有 BUILD/LAYOUT/PAINT 三个粗粒度区间。
const TRACKING_EXTS = [
	"ext.flutter.profileWidgetBuilds",
	"ext.flutter.profileUserWidgetBuilds",
	"ext.flutter.profileRenderObjectLayouts",
	"ext.flutter.profileRenderObjectPaints",
	"ext.flutter.profilePlatformChannels",
] as const;

// `--lean`：不开追踪。追踪每帧多发上百个事件，绝对 ms 会被抬高，只看帧率/掉帧率时用它。
const lean = process.argv.includes("--lean");

async function enableTracking(): Promise<void> {
	if (lean) return;
	for (const ext of TRACKING_EXTS) {
		const r = await call(ext, { isolateId: uiIsolate?.id, enabled: "true" });
		if (r.error) console.log(`${ext}: ${JSON.stringify(r.error).slice(0, 120)}`);
	}
}
await enableTracking();
console.log(lean ? "lean mode: widget tracking off" : "widget tracking on");

const nameIds = new Map<string, number>();
const newNames: string[] = [];
let cpuSamples = 0;
let lastCpuCursor = 0;
const threadNames = new Map<number, string>();
const spans: Span[] = [];
const openSpans = new Map<string, TraceEvent[]>();
let cursor = 0;

const pct = (values: readonly number[], p: number): number => {
	if (values.length === 0) return 0;
	const sorted = [...values].sort((a, b) => a - b);
	return sorted[Math.min(sorted.length - 1, Math.floor((sorted.length * p) / 100))] ?? 0;
};

function durationStats(label: string, arr: readonly Span[]) {
	const d = arr.map((e) => e.dur / 1000);
	const sum = d.reduce((a, b) => a + b, 0);
	return {
		label,
		count: d.length,
		avgMs: +(sum / (d.length || 1)).toFixed(2),
		p50: +pct(d, 50).toFixed(2),
		p90: +pct(d, 90).toFixed(2),
		p99: +pct(d, 99).toFixed(2),
		maxMs: +Math.max(0, ...d).toFixed(2),
		over11ms: d.filter((x) => x > 11.1).length,
		over22ms: d.filter((x) => x > 22.2).length,
	};
}

/// 连续帧起点间隔 → 实测刷新节奏；>1.5 个 90Hz 周期算掉帧。
function cadence(arr: readonly Span[]) {
	const ts = arr.map((e) => e.ts).sort((a, b) => a - b);
	const gaps: number[] = [];
	for (let i = 1; i < ts.length; i++) {
		const gap = ((ts[i] ?? 0) - (ts[i - 1] ?? 0)) / 1000;
		if (gap > 0 && gap < 200) gaps.push(gap);
	}
	const med = pct(gaps, 50);
	return {
		frames: ts.length,
		medianGapMs: +med.toFixed(2),
		impliedFps: med > 0 ? +(1000 / med).toFixed(1) : 0,
		p90GapMs: +pct(gaps, 90).toFixed(2),
		p99GapMs: +pct(gaps, 99).toFixed(2),
		gapsOver16ms: gaps.filter((g) => g > 16.7).length,
		gapsOver25ms: gaps.filter((g) => g > 25).length,
		total: gaps.length,
	};
}

/// 卡顿帧内部有哪些 span：同线程、时间区间被帧包住的子 span，按自身耗时排序。
function drill(frame: Span, all: readonly Span[]) {
	const end = frame.ts + frame.dur;
	const inside = all.filter((s) => s.tid === frame.tid && s !== frame && s.ts >= frame.ts && s.ts + s.dur <= end && s.dur > 300);
	const byName = new Map<string, { n: number; total: number }>();
	for (const s of inside) {
		const cur = byName.get(s.name) ?? { n: 0, total: 0 };
		cur.n += 1;
		cur.total += s.dur;
		byName.set(s.name, cur);
	}
	return [...byName.entries()]
		.sort((a, b) => b[1].total - a[1].total)
		.slice(0, 8)
		.map(([name, v]) => `${name} x${v.n} ${(v.total / 1000).toFixed(1)}ms`);
}

function report(arr: readonly Span[], tag: string) {
	const ui = arr.filter((e) => e.name === UI_FRAME && e.dur < 200_000);
	const raster = arr.filter((e) => e.name === RASTER_FRAME && e.dur < 200_000);
	return {
		tag,
		cadence: cadence(ui),
		ui: durationStats("ui build+layout+paint", ui),
		raster: durationStats("raster", raster),
		worstUi: [...ui].sort((a, b) => b.dur - a.dur).slice(0, 12).map((e) => ({ ms: +(e.dur / 1000).toFixed(2), ts: e.ts, inside: drill(e, arr) })),
		worstRaster: [...raster].sort((a, b) => b.dur - a.dur).slice(0, 12).map((e) => ({ ms: +(e.dur / 1000).toFixed(2), ts: e.ts, inside: drill(e, arr) })),
	};
}

async function poll(): Promise<void> {
	const res = await call("getVMTimeline");
	if (res.error) {
		console.log("timeline error", JSON.stringify(res.error));
		return;
	}
	const events = res.traceEvents ?? [];
	// 原始事件先原样落盘，分析全部离线做，避免任何信息在采集期被丢掉。
	if (events.length > 0) {
		appendFileSync(`${outDir}/raw_timeline.jsonl`, `${events.map((e) => JSON.stringify(e)).join("\n")}\n`);
	}
	for (const e of events) {
		if (e.tid === undefined) continue;
		if (e.ph === "M" && e.name === "thread_name") {
			threadNames.set(e.tid, e.args?.name ?? String(e.tid));
			continue;
		}
		if (e.ts === undefined) continue;
		if (e.ts > cursor) cursor = e.ts;
		if (e.ph === "X" && e.dur !== undefined) {
			spans.push({ name: e.name ?? "?", tid: e.tid, ts: e.ts, dur: e.dur });
			continue;
		}
		const key = `${e.tid}\u0000${e.name ?? "?"}`;
		if (e.ph === "B") {
			const stack = openSpans.get(key) ?? [];
			stack.push(e);
			openSpans.set(key, stack);
		} else if (e.ph === "E") {
			const begin = openSpans.get(key)?.pop();
			if (begin?.ts === undefined) continue;
			spans.push({ name: e.name ?? "?", tid: e.tid, ts: begin.ts, dur: e.ts - begin.ts });
		}
	}
	await call("clearVMTimeline");
	// 只留最近 30s 派生 span 用于实时进度显示；完整数据在 raw_timeline.jsonl。
	const keep = spans.filter((e) => e.ts >= cursor - 30_000_000);
	spans.length = 0;
	spans.push(...keep);
	const recent = report(spans.filter((e) => e.ts >= cursor - 2_100_000), "2s");
	appendFileSync(
		`${outDir}/history.jsonl`,
		`${JSON.stringify({ at: new Date().toISOString(), cursor, cadence: recent.cadence, uiP90: recent.ui.p90, uiMax: recent.ui.maxMs, rasterP90: recent.raster.p90, rasterMax: recent.raster.maxMs })}\n`,
	);
	console.log(`polled: events=${events.length} fps=${recent.cadence.impliedFps} jank16=${recent.cadence.gapsOver16ms}`);
}

async function dumpCpu(): Promise<void> {
	if (!uiIsolate) return;
	// 采样时间戳走设备 uptime 时钟（与 timeline 的 cursor 同源），窗口首尾相接避免重复计数。
	const origin = lastCpuCursor > 0 ? lastCpuCursor : Math.max(0, cursor - 6_000_000);
	const extent = Math.max(1_000_000, cursor - origin);
	lastCpuCursor = cursor;
	const r = await call("getCpuSamples", { isolateId: uiIsolate.id, timeOriginMicros: origin, timeExtentMicros: extent });
	if (r.error) {
		console.log("cpu error", JSON.stringify(r.error));
		return;
	}
	// functions 索引只在本次响应内有效，整张表 3 万条；翻成会话级稳定 id 只增量落盘，否则每次几十 MB。
	const localIds = (r.functions ?? []).map((f) => {
		const owner = f.function?.owner?.name;
		const raw = f.function?.name ?? "?";
		const full = raw.startsWith("[Native]") ? raw : `${owner ? `${owner}.` : ""}${raw}`;
		const existing = nameIds.get(full);
		if (existing !== undefined) return existing;
		const id = nameIds.size;
		nameIds.set(full, id);
		newNames.push(full);
		return id;
	});
	const samples = (r.samples ?? []).map((s) => ({ t: s.timestamp, s: (s.stack ?? []).map((i) => localIds[i] ?? -1) }));
	appendFileSync(
		`${outDir}/raw_cpu.jsonl`,
		`${JSON.stringify({ at: Date.now(), origin, extent, names: newNames.splice(0), samples })}\n`,
	);
	cpuSamples += samples.length;
	console.log(`cpu dump: +${samples.length} samples (session ${cpuSamples})`);
}

// 1s 拉一次：ring buffer 容量有限，拉得勤才不丢事件。
setInterval(() => void poll(), 1000);
setInterval(() => void dumpCpu(), 3000);
setInterval(() => void enableTracking(), 10_000);
