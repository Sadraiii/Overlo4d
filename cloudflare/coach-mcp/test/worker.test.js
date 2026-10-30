import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";

function kv() {
  const store = new Map();
  return {
    async get(key, type) {
      const value = store.get(key);
      return value === undefined ? null : type === "json" ? JSON.parse(value) : value;
    },
    async put(key, value) { store.set(key, value); },
  };
}

const TOKEN = "abcdefghijklmnopqrstuvwxyz123456";
const BASE = "https://overlo4d.example.workers.dev";
const snapshot = {
  format: 1,
  generatedAt: new Date().toISOString(),
  timeZone: "Europe/Stockholm",
  goal: "Get stronger",
  workouts: [
    { date: new Date().toISOString(), text: "## Push, today\n- Bench Press (Barbell): 80 kg × 5" },
    { date: "2020-01-01T10:00:00Z", text: "## Old" },
  ],
  exerciseHistory: { "Bench Press (Barbell)": "Bench Press (Barbell), 1 sessions" },
  exerciseNames: ["Bench Press (Barbell)", "Squat (Barbell)", "Face Pull (Cable)", "Incline Bench Press (Dumbbell)"],
  exercises: ["Bench Press (Barbell): Chest", "Squat (Barbell): Quads", "Face Pull (Cable): Rear delts"],
  weeklySets: ["Last 7 days: Chest 3"],
  sleep: [], food: [], body: [],
  plans: "## Push\n- Bench Press (Barbell): 3 × 5",
  planNames: ["Push"],
  programNames: [],
  programs: "",
};

const env = () => ({ COACH: kv() });
const api = (e, path, method = "GET", body, token = TOKEN) =>
  worker.fetch(new Request(BASE + path, {
    method, headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  }), e);
const rpc = async (e, method, params, token = TOKEN) => {
  const response = await worker.fetch(new Request(`${BASE}/mcp/${token}`, {
    method: "POST", headers: { "content-type": "application/json", accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  }), e);
  return response.status === 200 ? (await response.json()) : response.status;
};

test("first sync claims the server, another token is refused", async () => {
  const e = env();
  assert.equal((await api(e, "/api/sync", "POST", snapshot)).status, 200);
  assert.equal((await api(e, "/api/sync", "POST", snapshot, "x".repeat(32))).status, 403);
  assert.equal(await rpc(e, "tools/list", {}, "x".repeat(32)), 404);
});

test("MCP handshake and tools", async () => {
  const e = env();
  await api(e, "/api/sync", "POST", snapshot);
  const init = await rpc(e, "initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "1" } });
  assert.equal(init.result.protocolVersion, "2025-06-18");
  assert.ok(init.result.instructions.includes("Overlo4d"));
  const list = await rpc(e, "tools/list", {});
  assert.equal(list.result.tools.length, 12);
  const workouts = await rpc(e, "tools/call", { name: "get_workouts", arguments: { days: 7 } });
  assert.ok(workouts.result.content[0].text.includes("Bench"));
  assert.ok(!workouts.result.content[0].text.includes("Old"));
  const history = await rpc(e, "tools/call", { name: "get_exercise_history", arguments: { exercise: "bench press (barbell)" } });
  assert.ok(history.result.content[0].text.startsWith("Bench Press (Barbell)"));
  const overview = await rpc(e, "tools/call", { name: "get_overview", arguments: {} });
  assert.ok(overview.result.content[0].text.includes("Plans: Push"));
  const note = await worker.fetch(new Request(`${BASE}/mcp/${TOKEN}`, { method: "POST", body: JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) }), e);
  assert.equal(note.status, 202);
});

test("proposals reach the inbox and can be acknowledged", async () => {
  const e = env();
  await api(e, "/api/sync", "POST", snapshot);
  const bad = await rpc(e, "tools/call", { name: "propose_plan_change", arguments: { plan: "Pull", summary: "", changes: [] } });
  assert.equal(bad.result.isError, true);
  const good = await rpc(e, "tools/call", { name: "propose_plan_change", arguments: {
    plan: "push", summary: "More rear delts", changes: [{ action: "add", exercise: "face pull", new_exercise: "", sets: 3, reps: 15 }] } });
  assert.ok(!good.result.isError, good.result.content[0].text);
  const prog = await rpc(e, "tools/call", { name: "propose_program", arguments: {
    name: "Block", summary: "s", lifts: [{ exercise: "Squat (Barbell)", training_max_kg: 120, increment_kg: 2.5 }],
    days: [{ name: "A", lifts: ["Squat (Barbell)"], accessories: [] }],
    weeks: [{ phase: "W1", note: "", deload: false, amrap_target: 0, sets: [{ percent: 70, reps: 5, amrap: false, warmup: false }] }],
    rules: [] } });
  assert.ok(!prog.result.isError, prog.result.content[0].text);
  const inbox = await (await api(e, "/api/inbox")).json();
  assert.equal(inbox.items.length, 2);
  assert.equal(inbox.items[0].input.plan, "Push");
  assert.equal(inbox.items[0].input.changes[0].exercise, "Face Pull (Cable)");
  assert.equal(inbox.items[1].kind, "program");
  await api(e, "/api/inbox/ack", "POST", { ids: [inbox.items[0].id] });
  assert.equal((await (await api(e, "/api/inbox")).json()).items.length, 1);
});
