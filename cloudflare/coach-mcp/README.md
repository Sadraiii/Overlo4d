# Overlo4d coach server

A small Cloudflare Worker that lets Claude coach you with your normal Claude plan, no API key needed.
The app uploads your log to it, and Claude reads it through a custom connector (a remote MCP server).
Claude can also send plan changes and whole strength programs back. They show up on the app's Coach
screen with an Apply button.

It runs on Cloudflare's free plan and keeps everything in one KV namespace that's created on the first deploy.

## 1. Deploy

### From GitHub (no tools on your PC)

1. In the Cloudflare dashboard go to **Workers & Pages → Create → Import a repository** and pick this repo.
2. Name the Worker `overlo4d`. If you pick another name, change `name` in `wrangler.toml` to match.
3. Under **Build configuration**, set **Root directory** to `cloudflare/coach-mcp` and leave the deploy command as `npx wrangler deploy`.
4. Deploy. Every push to `main` deploys again.

If a build already failed with *Could not detect a directory containing static files*, the root directory
is missing. Set it in **Settings → Build → Build configuration** and retry the build.

### From a Windows PC

Install [Node.js](https://nodejs.org) (LTS), then in PowerShell:

```powershell
cd RepCounter\cloudflare\coach-mcp
npm install
npx wrangler login
npx wrangler deploy
```

### Check it

Wrangler, or the Worker's page in the dashboard, shows the address, like
`https://overlo4d.<your-subdomain>.workers.dev`. Opening it in a browser should show
"Overlo4d coach server".

## 2. Connect the app

In Overlo4d go to **Settings → AI coach → Claude connector**, paste the address and tap **Connect**.
The app makes a secret token, uploads your data, and shows the **connector address**
(`https://…workers.dev/mcp/<token>`). The first phone that connects claims the server. After that,
every request needs the same token.

The app uploads again whenever you leave it and something changed. **Sync now** uploads straight away.

## 3. Add the connector in Claude

1. Copy the connector address in the app.
2. In Claude (claude.ai in a browser or the desktop app), go to **Settings → Connectors → Add custom connector**.
3. Name it `Overlo4d` and paste the address. Leave the OAuth fields empty.
4. In a chat, turn the connector on from the tools menu, then ask, for example,
   *"How is my bench press going?"* or *"Write me an 8-week program for a bigger squat"*.

Connectors you add on the web also work in the Claude iPhone app.

## Tools

| Tool | What it does |
| --- | --- |
| `get_overview` | Last sync, goal, plans, programs, what's waiting in the app |
| `get_workouts` | Workouts from the last N days with every set |
| `get_exercise_history` | Every session of one exercise with estimated 1RM |
| `search_exercises` | Exact exercise names, muscles and equipment |
| `get_weekly_sets` | Hard sets per muscle per week |
| `get_sleep`, `get_food`, `get_body` | Sleep, food diary and measurements |
| `get_plans`, `get_programs` | Saved plans and strength programs |
| `propose_plan_change` | Sends a plan change to the app (applied only when you tap Apply) |
| `propose_program` | Sends a strength program to the app (added only when you tap Add) |

## Privacy and reset

Anyone with the connector address can read your log, so keep it private. To start over with a new
token, delete the `token` key in the Worker's KV namespace (**Storage & Databases → KV**), or run
`npx wrangler kv key delete token --binding COACH --remote`. Then connect from the app again.

## Tests

```sh
npm test
```
