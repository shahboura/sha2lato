# Self-hosting your Discord bot

sha2lato uses a **self-hosted bot**: you create your own Discord application, so the bot identity, avatar, and permissions are entirely under your control. It takes about five minutes.

## 1. Create the application

1. Open <https://discord.com/developers/applications> → **New Application** → give it a name (e.g. `sha2lato`).
2. Go to the **Bot** tab.
3. **Enable “Message Content Intent”** — required for Kimaki to read your messages. Without it, the bot connects but ignores everything.
4. Make sure **Public Bot** matches your preference (leave it on if you want the shareable install link to work for others; off for yourself only).
5. Click **Reset Token** → copy the token. It looks like `MTAx…abc.def.ghi` (three dot-separated segments).

> ⚠️ The token is a full-access credential for the bot. Paste it only into `secrets/.env.agent` on the host — never into Discord, chat, or a commit.

## 2. Wire it into sha2lato

On the host:

```bash
cd /opt/sha2lato
# put the token in the agent env file
$EDITOR secrets/.env.agent
```

```ini
KIMAKI_BOT_TOKEN=MTAxYourBotTokenHere...
MACHINE_NAME=sha2lato        # the Discord category will be "Kimaki sha2lato"
```

Then start the stack:

```bash
docker compose -f compose/docker-compose.yml up -d
```

On first start, Kimaki reads the token **headlessly**, starts the bot, and saves the credential to the data volume (`/data/kimaki.db`) — later restarts work even if you remove the token from the env file.

## 3. Invite the bot to your server

Kimaki derives your bot's invite URL from the token:

```bash
docker compose -f compose/docker-compose.yml exec agent kimaki bot install-url
```

Open the printed URL in a browser logged into Discord, pick your server (create a **dedicated server** for agents — recommended), and **Authorize**. The URL requests exactly the permissions Kimaki needs:

> View Channels, Manage Channels, Send Messages, Send Messages in Threads, Create Public Threads, Manage Threads, Read Message History, Attach Files, Add Reactions — plus the `applications.commands` scope for slash commands.

## 4. Finish onboarding

Once authorized, Kimaki creates a category **`Kimaki <MACHINE_NAME>`** with a `#kimaki` channel and an onboarding thread. If nothing appears within a minute (the bot was invited after its first boot), give it a nudge:

```bash
docker compose -f compose/docker-compose.yml restart agent
```

Then, in Discord:

1. Open the onboarding thread of your server and chat with the agent, or
2. Run **`/login`** in any channel — connect Claude Pro/Max, ChatGPT, Gemini, or an API key. Credentials are stored by OpenCode on the volume, so they survive restarts and image updates.

You are done. Send a message in `#kimaki` describing what you want, or tell the agent to clone a repo and add it as a project (see [usage.md](usage.md)).

## Access control

Kimaki only accepts messages from users with **one of**: Server Owner, **Manage Server**, **Administrator**, or a role named **`Kimaki`** (create it and assign it to trusted people — the recommended way for teams). Messages from other users are ignored.

To **block** someone (even an admin), give them a role named **`no-kimaki`**.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Bot online but ignores all messages | Message Content Intent is off (Bot tab → enable → restart agent) |
| `kimaki bot install-url` says no bot configured | The agent hasn't completed its first start — check `logs agent`, ensure `KIMAKI_BOT_TOKEN` is set, `up -d` again |
| Category/channels never appear | `docker compose … restart agent` after inviting the bot |
| Logs show `install_url`/gateway events, agent restart-loops | `KIMAKI_BOT_TOKEN` is missing or malformed — the box fell back to Kimaki's shared-bot onboarding. Set the token, `up -d` |
| Token was leaked | Developer Portal → Bot → Reset Token → update `secrets/.env.agent` → `up -d` (new token replaces the saved one) |

More failure modes: [troubleshooting.md](troubleshooting.md).
