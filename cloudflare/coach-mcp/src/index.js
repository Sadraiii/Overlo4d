// Overlo4d coach: a remote MCP server on a Cloudflare Worker.
//
// The app uploads a snapshot of the user's log (POST /api/sync). Claude reads it through the MCP
// endpoint (/mcp/<token>), added in Claude as a custom connector, and can leave plan changes and
// programs in an inbox that the app shows with Apply buttons (GET /api/inbox, POST /api/inbox/ack).
//
// The first sync claims the server: its token's hash is stored and every later request must
// carry the same token. Everything lives in one KV namespace bound as COACH.

const SERVER = { name: "overlo4d-coach", title: "Overlo4d coach", version: "1.0.0" };
const PROTOCOLS = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"];
const MAX_INBOX = 20;

const INSTRUCTIONS = `You are the coach for someone who logs their training in Overlo4d, a gym tracker on their iPhone. \
These tools read a copy of their log that the app uploads, and can send plan changes and programs back to the app.

How to coach:
- Start with get_overview to see what's there and when it was last synced. Look things up before answering \
questions about their training; don't guess what they did. Fetch only what the question needs.
- Quote actual exercises, weights, reps, dates and set counts. Weights are in kilograms.
- Judge volume in hard sets per muscle per week: about 10-20 is productive for most people, more than 20 is \
usually more than they recover from, and the same muscle trained hard again within 48 hours is short on recovery.
- For progress, look at whether weights or reps go up over the weeks; for stalls suggest rep ranges, a deload \
or a different variation.
- When they ask for a plan change, or one clearly follows from your advice, call propose_plan_change. To write \
a new multi-week strength program, call propose_program. Both only arrive in the app's Coach screen with an \
Apply button; nothing changes until the user taps it, so say so in your reply.
- If they follow a strength program, read it with get_programs before advising on their main lifts, and \
coach within it.
- You can't examine anyone. If they mention pain or injury, tell them to get it checked by a professional and \
don't prescribe around it.`;

// MARK: Tools

const obj = (properties, required = Object.keys(properties)) => ({
  type: "object",
  additionalProperties: false,
  properties,
  required,
});
const str = (description) => (description ? { type: "string", description } : { type: "string" });
const int = (description) => (description ? { type: "integer", description } : { type: "integer" });
const READ = { readOnlyHint: true, destructiveHint: false, openWorldHint: false };
const WRITE = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false };

const TOOLS = [
  {
    name: "get_overview",
    title: "Overview",
    description:
      "When the app last synced, their goal, how much is logged, their plans and programs, and proposals still waiting in the app. Call it first.",
    inputSchema: obj({}),
    annotations: READ,
  },
  {
    name: "get_workouts",
    title: "Workouts",
    description:
      "Workouts logged in the last `days` days (1-365), newest first, with every set (W warm-up, D drop, F failure), notes, and cardio from Apple Health.",
    inputSchema: obj({ days: int("How many days back, 1-365.") }),
    annotations: READ,
  },
  {
    name: "get_exercise_history",
    title: "Exercise history",
    description:
      "Every logged session of one exercise, oldest first, with its sets and estimated one-rep max. Use it to judge progress on a lift. If you're unsure of the name, call search_exercises first.",
    inputSchema: obj({ exercise: str("The exercise name, e.g. Bench Press (Barbell).") }),
    annotations: READ,
  },
  {
    name: "search_exercises",
    title: "Search exercises",
    description:
      "Exercises in the app's library and the user's own whose name or muscles match `query`, with muscles and equipment. Use it to find exact names before proposing changes.",
    inputSchema: obj({ query: str("Part of a name or a muscle, e.g. row or hamstrings.") }),
    annotations: READ,
  },
  {
    name: "get_weekly_sets",
    title: "Weekly sets",
    description: "Hard sets per muscle for each of the last `weeks` weeks (1-12), newest first. Warm-ups don't count; secondary muscles count half.",
    inputSchema: obj({ weeks: int("How many weeks back, 1-12.") }),
    annotations: READ,
  },
  {
    name: "get_sleep",
    title: "Sleep",
    description: "The last two weeks of sleep: times, hours, stages, scores, tags and the sleep goal.",
    inputSchema: obj({}),
    annotations: READ,
  },
  {
    name: "get_food",
    title: "Food",
    description: "The last week of the food diary: calories and macros per day against the goals, and body weight.",
    inputSchema: obj({}),
    annotations: READ,
  },
  {
    name: "get_body",
    title: "Body",
    description: "Body measurements with the change over the last month and since the first reading, and progress-photo days. Weight is in get_food.",
    inputSchema: obj({}),
    annotations: READ,
  },
  {
    name: "get_plans",
    title: "Plans",
    description: "The user's saved workout plans with each exercise and its target sets.",
    inputSchema: obj({}),
    annotations: READ,
  },
  {
    name: "get_programs",
    title: "Strength programs",
    description:
      "The user's multi-week strength programs: where they are, training maxes, every week's main-lift percentages, accessories, rep-out results and progression rules.",
    inputSchema: obj({}),
    annotations: READ,
  },
  {
    name: "propose_plan_change",
    title: "Propose a plan change",
    description:
      "Sends changes to one of the user's saved plans to the app, where they appear on the Coach screen with an Apply button. Use exact plan and exercise names from get_plans and search_exercises. Actions: add (append `exercise` with `sets` sets of `reps`), remove (`exercise`), replace (`exercise` with `new_exercise`, keeping its sets), set_sets (set `exercise` to `sets` sets of `reps`). Use 0 for sets or reps you don't set and an empty string for an unused new_exercise.",
    inputSchema: obj({
      plan: str("The plan's name."),
      summary: str("What the change does and why, in one or two sentences."),
      changes: {
        type: "array",
        minItems: 1,
        items: obj({
          action: { type: "string", enum: ["add", "remove", "replace", "set_sets"] },
          exercise: str(),
          new_exercise: str(),
          sets: int(),
          reps: int(),
        }),
      },
    }),
    annotations: WRITE,
  },
  {
    name: "propose_program",
    title: "Propose a strength program",
    description:
      "Sends a multi-week strength program to the app, where it appears on the Coach screen with an Add button and then runs from the Plans tab with weights filled in. Main lifts run off a training max (about 90 % of the one-rep max) and are prescribed per week as percentages of it, the same sets for every main lift that week. Use warmup true for ramp-up sets and amrap true only on a week's final rep-out set, with amrap_target the reps to beat (0 when none). Increment is the kilograms added per rep beaten on a rep-out set (about 2.5 for lower body, 1.25 for presses). deload true halves accessory sets. Use exact exercise names from search_exercises.",
    inputSchema: obj({
      name: str("Short program name, e.g. 12-week bench focus."),
      summary: str("Two sentences on how the program works and why it fits them."),
      lifts: {
        type: "array",
        items: obj({ exercise: str(), training_max_kg: { type: "number" }, increment_kg: { type: "number" } }),
      },
      days: {
        type: "array",
        description: "The training days of every week, in order.",
        items: obj({
          name: str("e.g. Squat day or Upper A."),
          lifts: { type: "array", items: { type: "string" }, description: "Main lifts trained this day, by exercise name." },
          accessories: { type: "array", items: obj({ exercise: str(), sets: int(), reps: int(), notes: str() }) },
        }),
      },
      weeks: {
        type: "array",
        description: "Every week in order.",
        items: obj({
          phase: str("e.g. 10s wave · Accumulation or Week 3 · Strength."),
          note: str("What the week is for, one sentence."),
          deload: { type: "boolean" },
          amrap_target: int("Reps to beat on the rep-out set, or 0 when the week has none."),
          sets: {
            type: "array",
            items: obj({ percent: { type: "number" }, reps: int(), amrap: { type: "boolean" }, warmup: { type: "boolean" } }),
          },
        }),
      },
      rules: { type: "array", items: { type: "string" }, description: "3-6 short sentences on how to progress, and what to do after a missed rep-out." },
    }),
    annotations: WRITE,
  },
];

// MARK: Snapshot helpers

const clamp = (value, low, high, fallback) => {
  const number = Number.isFinite(value) ? Math.round(value) : fallback;
  return Math.min(Math.max(number, low), high);
};
const bullets = (lines, empty) => (lines && lines.length ? lines.map((line) => `- ${line}`).join("\n") : empty);

/// An exercise name from the snapshot: exact (ignoring case), or a unique partial match, like the app does.
function findExercise(snapshot, name) {
  const wanted = String(name ?? "").trim().toLowerCase();
  if (!wanted) return null;
  const names = snapshot.exerciseNames ?? [];
  const exact = names.find((candidate) => candidate.toLowerCase() === wanted);
  if (exact) return exact;
  const partial = names.filter((candidate) => candidate.toLowerCase().includes(wanted));
  return partial.length === 1 ? partial[0] : null;
}

function ago(iso, now) {
  const minutes = Math.round((now - Date.parse(iso)) / 60000);
  if (!Number.isFinite(minutes)) return "unknown";
  if (minutes < 2) return "just now";
  if (minutes < 120) return `${minutes} minutes ago`;
  const hours = Math.round(minutes / 60);
  return hours < 48 ? `${hours} hours ago` : `${Math.round(hours / 24)} days ago`;
}

// MARK: Tool calls

async function callTool(env, name, args, now) {
  const snapshot = await env.COACH.get("snapshot", "json");
  if (!snapshot) {
    return error("Nothing synced yet. Ask them to open Overlo4d, go to Settings > Claude connector and tap Sync now.");
  }
  args = args ?? {};
  switch (name) {
    case "get_overview": {
      const inbox = (await env.COACH.get("inbox", "json")) ?? [];
      const lines = [
        `Synced ${ago(snapshot.generatedAt, now)} (${snapshot.generatedAt}), their time zone ${snapshot.timeZone}.`,
        `Now: ${new Date(now).toISOString()}.`,
        snapshot.goal ? `Goal: ${snapshot.goal}.` : null,
        `${snapshot.workouts.length} workouts in the last year${snapshot.workouts[0] ? `, the latest on ${snapshot.workouts[0].date}` : ""}.`,
        `${Object.keys(snapshot.exerciseHistory ?? {}).length} exercises logged, ${snapshot.exerciseNames.length} in the library.`,
        `Plans: ${snapshot.planNames.length ? snapshot.planNames.join(", ") : "none"}.`,
        `Programs: ${snapshot.programNames?.length ? snapshot.programNames.join(", ") : "none"}.`,
        `Tracks sleep: ${snapshot.sleep.length ? "yes" : "no"}. Logs food: ${snapshot.food.length ? "yes" : "no"}. Measures body: ${snapshot.body.length ? "yes" : "no"}.`,
        inbox.length
          ? `Waiting in the app for them to apply: ${inbox.map((item) => `${item.title} (${ago(item.createdAt, now)})`).join("; ")}.`
          : "Nothing waiting in the app.",
      ];
      return text(lines.filter(Boolean).join("\n"));
    }
    case "get_workouts": {
      const days = clamp(args.days, 1, 365, 28);
      const since = now - days * 86_400_000;
      const recent = snapshot.workouts.filter((workout) => Date.parse(workout.date) >= since);
      return text(recent.length ? recent.map((workout) => workout.text).join("\n") : `No workouts in the last ${days} days.`);
    }
    case "get_exercise_history": {
      const match = findExercise(snapshot, args.exercise);
      if (!match) return error(`No exercise called ${args.exercise}. Try search_exercises.`);
      return text(snapshot.exerciseHistory[match] ?? `${match} hasn't been logged yet.`);
    }
    case "search_exercises": {
      const words = String(args.query ?? "").toLowerCase().split(/\s+/).filter(Boolean);
      const matches = snapshot.exercises.filter((line) => words.every((word) => line.toLowerCase().includes(word)));
      return text(matches.length ? matches.slice(0, 40).map((line) => `- ${line}`).join("\n") : `No exercises match ${args.query}.`);
    }
    case "get_weekly_sets":
      return text(bullets(snapshot.weeklySets.slice(0, clamp(args.weeks, 1, 12, 4)), "No sets logged."));
    case "get_sleep":
      return text(bullets(snapshot.sleep, "They don't track sleep."));
    case "get_food":
      return text(bullets(snapshot.food, "They don't log food."));
    case "get_body":
      return text(bullets(snapshot.body, "No body measurements logged."));
    case "get_plans":
      return text(snapshot.plans || "No saved plans.");
    case "get_programs":
      return text(snapshot.programs || "No strength programs yet.");
    case "propose_plan_change":
      return propose(env, now, planChange(snapshot, args));
    case "propose_program":
      return propose(env, now, program(snapshot, args));
    default:
      return error(`There is no tool called ${name}.`);
  }
}

/// Checks a plan change against the snapshot so mistakes come back to Claude, not to the user.
function planChange(snapshot, args) {
  const plan = snapshot.planNames.find((name) => name.toLowerCase() === String(args.plan ?? "").trim().toLowerCase());
  if (!plan) return { problem: `No plan called ${args.plan}. Plans: ${snapshot.planNames.join(", ") || "none"}.` };
  const changes = Array.isArray(args.changes) ? args.changes : [];
  if (!changes.length) return { problem: "Add at least one change." };
  const cleaned = [];
  for (const change of changes) {
    if (!["add", "remove", "replace", "set_sets"].includes(change.action)) return { problem: `Unknown action ${change.action}.` };
    const exercise = findExercise(snapshot, change.exercise);
    if (!exercise) return { problem: `No exercise called ${change.exercise}. Use search_exercises for exact names.` };
    let newExercise = "";
    if (change.action === "replace") {
      newExercise = findExercise(snapshot, change.new_exercise);
      if (!newExercise) return { problem: `No exercise called ${change.new_exercise}. Use search_exercises for exact names.` };
    }
    const sets = clamp(change.sets, 0, 20, 0);
    const reps = clamp(change.reps, 0, 100, 0);
    if (change.action === "set_sets" && !sets && !reps) return { problem: `Give sets or reps for ${exercise}.` };
    cleaned.push({ action: change.action, exercise, new_exercise: newExercise, sets, reps });
  }
  return {
    kind: "plan_change",
    title: `Change to ${plan}`,
    input: { plan, summary: String(args.summary ?? ""), changes: cleaned },
  };
}

function program(snapshot, args) {
  const lifts = Array.isArray(args.lifts) ? args.lifts : [];
  const days = Array.isArray(args.days) ? args.days : [];
  const weeks = Array.isArray(args.weeks) ? args.weeks : [];
  if (!days.length || !weeks.length) return { problem: "A program needs at least one day and one week." };
  if (weeks.length > 24 || days.length > 7) return { problem: "Keep it to 24 weeks and 7 days a week at most." };
  const names = [
    ...lifts.map((lift) => lift.exercise),
    ...days.flatMap((day) => [...(day.lifts ?? []), ...(day.accessories ?? []).map((accessory) => accessory.exercise)]),
  ];
  const unknown = [...new Set(names.filter((name) => !findExercise(snapshot, name)))];
  if (unknown.length) return { problem: `Unknown exercises: ${unknown.join(", ")}. Use search_exercises for exact names.` };
  // Exact library spelling, so the app links the program to the exercises they already log.
  const exact = (name) => findExercise(snapshot, name);
  const input = {
    name: String(args.name ?? ""),
    summary: String(args.summary ?? ""),
    lifts: lifts.map((lift) => ({
      exercise: exact(lift.exercise),
      training_max_kg: Number(lift.training_max_kg) || 0,
      increment_kg: Number(lift.increment_kg) || 0,
    })),
    days: days.map((day) => ({
      name: String(day.name ?? ""),
      lifts: (day.lifts ?? []).map(exact),
      accessories: (day.accessories ?? []).map((accessory) => ({
        exercise: exact(accessory.exercise),
        sets: clamp(accessory.sets, 1, 10, 3),
        reps: clamp(accessory.reps, 1, 50, 10),
        notes: String(accessory.notes ?? ""),
      })),
    })),
    weeks: weeks.map((week) => ({
      phase: String(week.phase ?? ""),
      note: String(week.note ?? ""),
      deload: Boolean(week.deload),
      amrap_target: clamp(week.amrap_target, 0, 30, 0),
      sets: (week.sets ?? []).map((set) => ({
        percent: Number(set.percent) || 0,
        reps: clamp(set.reps, 1, 30, 5),
        amrap: Boolean(set.amrap),
        warmup: Boolean(set.warmup),
      })),
    })),
    rules: (args.rules ?? []).map(String),
  };
  if (!input.lifts.some((lift) => lift.training_max_kg > 0) && !input.days.some((day) => day.accessories.length)) {
    return { problem: "Give the main lifts a training max, or the days some accessories." };
  }
  return { kind: "program", title: `Program: ${input.name || `${weeks.length}-week program`}`, input };
}

async function propose(env, now, proposal) {
  if (proposal.problem) return error(proposal.problem);
  const inbox = (await env.COACH.get("inbox", "json")) ?? [];
  inbox.push({ id: crypto.randomUUID(), createdAt: new Date(now).toISOString(), ...proposal });
  await env.COACH.put("inbox", JSON.stringify(inbox.slice(-MAX_INBOX)));
  return text(
    `Sent to Overlo4d: ${proposal.title}. It shows on the Coach screen with an Apply button the next time they open the app; nothing changes until they tap it.`,
  );
}

const text = (value) => ({ content: [{ type: "text", text: value }] });
const error = (value) => ({ content: [{ type: "text", text: value }], isError: true });

// MARK: MCP (Streamable HTTP, JSON responses, no sessions)

async function handleRpc(env, message, now) {
  const { id, method, params } = message ?? {};
  const isRequest = id !== undefined && id !== null;
  const reply = (result) => ({ jsonrpc: "2.0", id, result });
  const fail = (code, text) => ({ jsonrpc: "2.0", id: isRequest ? id : null, error: { code, message: text } });

  if (message?.jsonrpc !== "2.0" || typeof method !== "string") return isRequest ? fail(-32600, "Invalid request") : null;
  if (!isRequest) return null; // Notifications such as notifications/initialized need no answer.

  switch (method) {
    case "initialize": {
      const asked = params?.protocolVersion;
      return reply({
        protocolVersion: PROTOCOLS.includes(asked) ? asked : PROTOCOLS[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER,
        instructions: INSTRUCTIONS,
      });
    }
    case "ping":
      return reply({});
    case "tools/list":
      return reply({ tools: TOOLS });
    case "tools/call": {
      if (!TOOLS.some((tool) => tool.name === params?.name)) return fail(-32602, `Unknown tool: ${params?.name}`);
      return reply(await callTool(env, params.name, params.arguments, now));
    }
    case "resources/list":
      return reply({ resources: [] });
    case "prompts/list":
      return reply({ prompts: [] });
    default:
      return fail(-32601, `Method not found: ${method}`);
  }
}

async function handleMcp(request, env) {
  if (request.method !== "POST") {
    // No server-initiated stream; clients fall back to plain POSTs.
    return new Response("Method not allowed", { status: 405, headers: { allow: "POST" } });
  }
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } }, 400);
  }
  const now = Date.now();
  if (Array.isArray(body)) {
    const replies = (await Promise.all(body.map((message) => handleRpc(env, message, now)))).filter(Boolean);
    return replies.length ? json(replies) : new Response(null, { status: 202 });
  }
  const reply = await handleRpc(env, body, now);
  return reply ? json(reply) : new Response(null, { status: 202 });
}

// MARK: App API

async function sha256(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/// "ok", "unclaimed" or "wrong". Compares hashes, so the comparison doesn't leak the token's length or prefix.
async function checkToken(env, token) {
  if (!token || token.length < 20) return "wrong";
  const stored = await env.COACH.get("token");
  if (!stored) return "unclaimed";
  return stored === (await sha256(token)) ? "ok" : "wrong";
}

async function handleApi(request, env, path) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const state = await checkToken(env, token);
  const now = new Date().toISOString();

  if (path === "/api/sync" && request.method === "POST") {
    if (state === "wrong") return json({ error: "This server is linked to another token." }, 403);
    let snapshot;
    try {
      snapshot = await request.json();
    } catch {
      return json({ error: "Not JSON." }, 400);
    }
    if (snapshot?.format !== 1 || !Array.isArray(snapshot.workouts)) return json({ error: "Not an Overlo4d snapshot." }, 400);
    if (state === "unclaimed") await env.COACH.put("token", await sha256(token));
    await env.COACH.put("snapshot", JSON.stringify(snapshot));
    return json({ ok: true, syncedAt: now });
  }
  if (state !== "ok") return json({ error: state === "unclaimed" ? "Sync from the app first." : "Wrong token." }, 403);

  if (path === "/api/inbox" && request.method === "GET") {
    return json({ items: (await env.COACH.get("inbox", "json")) ?? [] });
  }
  if (path === "/api/inbox/ack" && request.method === "POST") {
    const { ids } = await request.json().catch(() => ({}));
    const done = new Set(Array.isArray(ids) ? ids : []);
    const inbox = (await env.COACH.get("inbox", "json")) ?? [];
    const left = inbox.filter((item) => !done.has(item.id));
    if (left.length !== inbox.length) await env.COACH.put("inbox", JSON.stringify(left));
    return json({ ok: true, left: left.length });
  }
  return json({ error: "Not found." }, 404);
}

const json = (value, status = 200) =>
  new Response(JSON.stringify(value), { status, headers: { "content-type": "application/json" } });

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname.replace(/\/+$/, "") || "/";
    if (path.startsWith("/api/")) return handleApi(request, env, path);

    const mcp = path.match(/^\/mcp\/([^/]+)$/);
    if (mcp) {
      if ((await checkToken(env, decodeURIComponent(mcp[1]))) !== "ok") return new Response("Not found", { status: 404 });
      return handleMcp(request, env);
    }
    if (path === "/") {
      return new Response("Overlo4d coach server. Add /mcp/<token> as a custom connector in Claude; the app shows the full address.", {
        headers: { "content-type": "text/plain; charset=utf-8" },
      });
    }
    return new Response("Not found", { status: 404 });
  },
};

// For tests.
export { handleRpc, planChange, program, findExercise, TOOLS };
