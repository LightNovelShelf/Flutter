/// 驱动真机上的 `ext.lightnovel.bench`（见 lib/dev/bench.dart）。
/// 用法: bun tool/bench.ts <vmServiceHttpUri> [iterations] [rounds] [case...]

type BenchResult = {
	readonly case?: string;
	readonly iterations?: number;
	readonly medianUs?: number;
	readonly minUs?: number;
	readonly maxUs?: number;
	readonly usPerOp?: number;
	readonly cases?: readonly string[];
};

const httpUri = process.argv[2];
if (!httpUri) throw new Error("need vm service uri");
const iterations = Number(process.argv[3] ?? 200);
const rounds = Number(process.argv[4] ?? 5);
const only = process.argv.slice(5);

const ws = new WebSocket(`${httpUri.replace(/^http/, "ws").replace(/\/$/, "")}/ws`);
let seq = 0;
const pending = new Map<string, (value: { result?: unknown; error?: unknown }) => void>();

ws.addEventListener("message", (ev: MessageEvent) => {
	const msg = JSON.parse(String(ev.data)) as { id?: string; result?: unknown; error?: unknown };
	const resolve = msg.id ? pending.get(msg.id) : undefined;
	if (!msg.id || !resolve) return;
	pending.delete(msg.id);
	resolve(msg);
});

function call(method: string, params: Record<string, unknown> = {}) {
	const id = String(++seq);
	const { promise, resolve } = Promise.withResolvers<{ result?: unknown; error?: unknown }>();
	pending.set(id, resolve);
	ws.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }));
	return promise;
}

{
	const { promise, resolve } = Promise.withResolvers<void>();
	ws.addEventListener("open", () => resolve());
	await promise;
}

const vm = (await call("getVM")).result as { isolates?: readonly { id: string; name?: string }[] };
const isolate = (vm.isolates ?? []).find((i) => i.name?.includes("main")) ?? vm.isolates?.[0];
if (!isolate) throw new Error("no isolate");

async function bench(params: Record<string, unknown>): Promise<BenchResult> {
	const r = await call("ext.lightnovel.bench", { isolateId: isolate.id, ...params });
	if (r.error) throw new Error(JSON.stringify(r.error).slice(0, 300));
	return r.result as BenchResult;
}

const listed = await bench({});
const cases = only.length > 0 ? only : (listed.cases ?? []);
console.log(`iterations=${iterations} rounds=${rounds}\n`);
console.log("case".padEnd(28), "us/op".padStart(10), "median".padStart(10), "min".padStart(9));
for (const name of cases) {
	const r = await bench({ case: name, iterations: String(iterations), rounds: String(rounds) });
	console.log(
		name.padEnd(28),
		(r.usPerOp ?? 0).toFixed(3).padStart(10),
		`${r.medianUs}us`.padStart(10),
		`${r.minUs}us`.padStart(9),
	);
}
process.exit(0);
