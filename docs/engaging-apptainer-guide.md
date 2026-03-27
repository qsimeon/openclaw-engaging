# Deploy OpenClaw on MIT Engaging with Apptainer

> **TL;DR** — Two commands: build the container, run the setup wizard. The
> wizard walks you through API keys, model selection, channels, and skills —
> just like the [DigitalOcean 1-Click Deploy](https://marketplace.digitalocean.com/apps/openclaw),
> but on Engaging's compute with your data already there. Sessions survive
> job preemption automatically.

---

## Why OpenClaw on Engaging?

[OpenClaw](https://github.com/openclaw/openclaw) is the open-source AI
assistant platform behind the
[DigitalOcean 1-Click Deploy](https://www.digitalocean.com/blog/moltbot-on-digitalocean)
and the [Docker quick-start](https://docs.openclaw.ai/install/docker). It
gives you multi-turn conversations, tool use, persistent memory, and
multi-channel messaging — all powered by your choice of LLM provider
(Anthropic Claude, OpenAI GPT-4o, Google Gemini, OpenRouter, etc.).

On DigitalOcean you get a persistent droplet. On Engaging you get something
better: **your research data is already there**, along with flexible compute
you can scale up on demand. No GPU needed — the agent calls cloud LLM APIs
over HTTPS.

**What this enables for MIT staff and researchers:**

- Launch AI agents that read and reason over your scientific data — without
  moving anything off-cluster
- Run long-running analysis as SLURM batch jobs overnight
- Use interactive sessions during the day, batch jobs at night
- All conversation history and agent state lives next to the repo —
  survives job preemption, node failures, and cluster maintenance
- Share a single container image across your lab; each user's config and
  sessions are isolated in their own `.openclaw/` directory

---

## How It Works

```
┌─────────────────────────────────────────────┐
│  Engaging Cluster                           │
│                                             │
│  ┌───────────────────────────────────────┐  │
│  │  Apptainer Container (openclaw.sif)   │  │
│  │  ┌─────────────┐  ┌───────────────┐   │  │
│  │  │ Node.js 22  │  │  OpenClaw CLI  │   │  │
│  │  └─────────────┘  └───────┬───────┘   │  │
│  └────────────────────────────┼───────────┘  │
│                               │              │
│  .openclaw/    ◄──────────────┘  (state)     │
│  (extra dirs: APPTAINER_BIND=... openclaw)  │
│                               │              │
└───────────────────────────────┼──────────────┘
                                │ HTTPS
                    ┌───────────▼───────────┐
                    │  LLM Provider APIs    │
                    │  (Anthropic, OpenAI,  │
                    │   OpenRouter, etc.)   │
                    └───────────────────────┘
```

- The **container** bundles Node.js and the OpenClaw application (read-only)
- The container's **home** is set to the parent of the repo — `.openclaw/`
  stores all config, sessions, and memory next to it (persistent across jobs)
- The agent makes **outbound HTTPS calls** to your chosen LLM provider
- Minimal resources: ~1 GB RAM, 1 CPU, **no GPU**, any partition. The agent
  itself does not need a GPU — it can submit SLURM jobs that request their
  own GPUs when needed (see [SLURM access](#slurm-access-from-inside-the-container-openclaw_slurm_binds)).
  Do not reserve GPU nodes for the agent or gateway; it wastes scarce resources

---

## Prerequisites

1. **An MIT Engaging account** — [request one here](https://engaging-web.mit.edu/)
2. **An API key** from any of these providers (have it ready — the wizard
   will ask):
   - [Anthropic](https://console.anthropic.com/) — recommended for Claude
     (`sk-ant-...`)
   - [OpenRouter](https://openrouter.ai/) — one key, many models (`sk-or-...`)
   - [OpenAI](https://platform.openai.com/) — GPT-4o and friends (`sk-...`)
3. **Know your login node** — the hostname you SSH into (e.g.,
   `eofe10.mit.edu` or `orcd-login.mit.edu`). You'll need this for SSH
   tunneling later.

---

## Step 1: Install (one command)

SSH into Engaging, then run the installer:

```bash
ssh <username>@orcd-login.mit.edu
curl -fsSL https://raw.githubusercontent.com/qsimeon/openclaw-engaging/main/install_stage0.sh | bash
```

This clones the repo to `~/orcd/scratch/oclaw/openclaw-engaging` and sets
up the upstream remote. Takes about 30 seconds.

> **Why scratch?** Cloning to scratch (not your home directory) means the
> container's `$HOME` is `~/orcd/scratch/oclaw/` — the agent can only
> see files in that directory, not your real home (`~/.ssh/`, `~/.gnupg/`, etc.).
> All OpenClaw state (`.openclaw/`) lives next to the repo automatically.

<details>
<summary>Manual clone (alternative)</summary>

```bash
mkdir -p ~/orcd/scratch/oclaw && cd ~/orcd/scratch/oclaw
git clone https://github.com/qsimeon/openclaw-engaging.git
cd openclaw-engaging
git remote add upstream https://github.com/openclaw/openclaw.git
```

</details>

---

## Step 2: Build + Configure (~15–20 min)

This is the Engaging equivalent of DigitalOcean's 1-Click Deploy. One command
builds the container and launches the interactive setup wizard — the same
wizard used on DigitalOcean. Stay at the terminal for this one:

```bash
cd ~/orcd/scratch/oclaw/openclaw-engaging
srun --pty --mem=8G --time=01:00:00 --cpus-per-task=2 ./apptainer/setup.sh
```

The build takes ~10–15 min, then the wizard takes ~5 min.

<details>
<summary>Split into two steps (if you need to walk away during the build)</summary>

```bash
# Step 2a: build only — submit and walk away (~10-15 min, no --pty needed)
srun --mem=8G --time=01:00:00 --cpus-per-task=2 ./apptainer/setup.sh --build-only

# Step 2b: wizard only — stay at terminal (~5 min)
srun --pty --mem=4G --time=00:30:00 ./apptainer/setup.sh --onboard-only
```

</details>

The wizard walks you through API key, model, channels, and skills. When it
finishes, HPC-specific settings are applied automatically:

- **Filesystem isolation: on** — `--containall` by default (agent can't see `~/.ssh/`, etc.)
- **Sandbox: off** — Apptainer is the security boundary (Docker-in-Docker not available)
- **Session idle timeout: 1 year** — sessions survive job preemption
- **Gateway: loopback bind, port 18790** — access via SSH tunnel

### What the wizard covers

1. **LLM provider** — pick Anthropic, OpenAI, OpenRouter, or others
2. **API key** — paste your key (stored in `.openclaw/.env` next to the repo)
3. **Model selection** — choose your default model
4. **Channels** (optional) — connect Telegram, Discord, Slack, etc.
5. **Skills** (optional) — enable web search, file tools, and more

> **Skill install failures are normal.** Some skills require Homebrew taps
> that can't be installed inside the read-only container. You'll see
> "brew not installed" errors — **this is fine**. The core agent and most
> skills (web search, file tools, code execution, etc.) work regardless.

> **Health check "SECURITY ERROR" about ws://.** The wizard warns that the
> gateway uses plaintext `ws://` on a non-loopback address. This is expected
> — on Engaging you connect via an encrypted SSH tunnel, so the traffic is
> secure. You can safely ignore this warning.

<details>
<summary>Manual onboarding (without setup.sh)</summary>

```bash
srun --pty --mem=1G --time=00:30:00 bash
module load apptainer/1.4.2
apptainer exec apptainer/openclaw.sif openclaw onboard --skip-daemon
openclaw config set agents.defaults.sandbox.mode off
```

</details>

---

## Step 3: Activate the `openclaw` Command

`setup.sh` installs a Lmod modulefile to `~/modulefiles/openclaw.lua`
automatically. To use it, add `module use ~/modulefiles` to your `~/.bashrc`
once (this is standard practice on Engaging — many tools do the same):

```bash
echo 'module use ~/modulefiles' >> ~/.bashrc
source ~/.bashrc
```

Then load OpenClaw whenever you want it:

```bash
module load openclaw
```

Or add that line to your `~/.bashrc` too, so `openclaw` is always available:

```bash
echo 'module load openclaw' >> ~/.bashrc
```

Verify it works:

```bash
openclaw --help
openclaw --version
```

> **Tip:** The module sets `OPENCLAW_CONTAINALL=1` by default (filesystem isolation on).
> To run without isolation: `OPENCLAW_CONTAINALL=0 openclaw agent ...`

---

## Step 4: Use Your Agent

Once onboarding is done, you have a fully configured agent. Here are the
three ways to use it:

### One-shot query

```bash
openclaw agent --local --agent main -m "Hello from Engaging!"
```

### Interactive session on a compute node

```bash
srun --pty --mem=1G --time=02:00:00 bash
openclaw agent --local --agent main -m "I have CSV files in ~/my-project/data/. Help me explore them."
```

### Batch job (unattended)

```bash
cd ~/orcd/scratch/oclaw/openclaw-engaging
OPENCLAW_PROMPT="Summarize all CSV files in ~/my-project/data/" sbatch apptainer/slurm-openclaw.sh
```

Output goes to `openclaw-<jobid>.out`.

### Binding extra directories

By default the agent can only see the repo and `.openclaw/`. To give it access
to additional data:

```bash
APPTAINER_BIND="/pool/lab-data" openclaw agent --local --agent main -m "Analyze the datasets in /pool/lab-data/"
```

---

## Step 5: Gateway & Dashboard (Browser Access)

The gateway is a long-running server that serves the web dashboard and
processes messages from connected channels (Telegram, Discord, etc.). On
DigitalOcean it runs as a systemd service and you access it directly at
`http://<droplet-ip>:18789/`. On Engaging, you run it as a SLURM job and
reach it from your laptop via SSH tunnel.

### Start the gateway

> **No GPU needed.** The gateway is a lightweight Node.js server — it needs
> only 1 CPU and 4 GB RAM. Do **not** request a GPU partition (`--gres=gpu:*`
> or `-p gpu-*`). The agent does not need a GPU in its workspace — when
> your agent needs GPU compute, it can submit SLURM jobs that request their
> own GPUs (via `OPENCLAW_SLURM_BINDS=1`). Reserving a GPU node for the
> gateway or agent session just wastes scarce shared resources.

The launcher submits the SLURM job, waits for it to start, and prints the
connection info automatically — no need to hunt for output files:

```bash
cd ~/orcd/scratch/oclaw/openclaw-engaging
./apptainer/start-gateway.sh
```

If a gateway is already running, it shows the existing connection info
instead of starting a second one.

> **Manual alternative:** `sbatch apptainer/slurm-gateway.sh` then
> `cat openclaw-gw-<jobid>.out` to see the connection info.

You'll see output like:

```
  1) SSH tunnel (run on your laptop — kills any old tunnel first):

     lsof -ti:18790 | xargs kill -9 2>/dev/null; sleep 1; ssh -f -N -J <user>@orcd-login.mit.edu -L 18790:localhost:18790 <user>@node1234

  2) Open in your browser:

     http://localhost:18790/?token=abc123...
```

### Connect from your laptop

**a) Open the SSH tunnel.** On your local machine, copy and run the exact
tunnel command from the job output — it already has the node name filled in:

```bash
lsof -ti:18790 | xargs kill -9 2>/dev/null; sleep 1; ssh -f -N -J <username>@orcd-login.mit.edu -L 18790:localhost:18790 <username>@<node>
```

The `-J` flag uses ProxyJump: your laptop connects to the login node, then
hops to the compute node. The gateway listens on localhost only, so this is
the only way to reach it.

The `lsof ... | xargs kill` prefix clears any stale tunnel first (safe to
run even if no tunnel is open). The `sleep 1` gives the OS time to release
the port.

| Placeholder | Replace with |
|---|---|
| `<node>` | Compute node from the output (e.g., `node1606`) |
| `<username>` | Your Engaging username |

Add these to your `~/.ssh/config` to detect dead connections automatically:

```
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

If the tunnel drops (e.g., after laptop sleep), just re-run the same command.

**b) Open the dashboard.** Paste the full URL from the job output into your
browser. The URL includes the auth token (`?token=...`), which authenticates
you automatically.

```
http://localhost:18790/?token=abc123...
```

### How it all connects

```
your-browser → localhost:18790 → SSH tunnel → login node → compute node:18790 (gateway)
```

The SSH tunnel is encrypted end-to-end, so the connection is secure even
though the dashboard uses HTTP (not HTTPS). The `setup.sh` script
pre-configures `gateway.controlUi.dangerouslyDisableDeviceAuth: true` so
the dashboard works over SSH tunnel without requiring additional device
pairing — token auth alone is sufficient.

> **If you ran onboarding manually** (Option B) and see "pairing required"
> when opening the dashboard, add this to `.openclaw/openclaw.json` (in the
> parent directory of the repo) inside the `"gateway"` section:
> ```json
> "controlUi": { "dangerouslyDisableDeviceAuth": true }
> ```
> Then restart the gateway job.

### How long does the gateway run?

The default SLURM script requests 8 hours. While running, the gateway
processes channel messages (Telegram, Discord, etc.) and serves the
dashboard. When the job ends, channels go offline but all state is saved —
just resubmit.

> **Tip:** For a longer-running gateway, increase `--time` in
> `slurm-gateway.sh` (e.g., `--time=24:00:00`). Check your partition's max
> wall time with `sinfo -p <partition> -o "%l"`.

### Customizing the gateway

```bash
# Change the port
OPENCLAW_GATEWAY_PORT=19000 sbatch apptainer/slurm-gateway.sh

# Change the login node shown in the job output
OPENCLAW_LOGIN_NODE=orcd-login.mit.edu sbatch apptainer/slurm-gateway.sh
```

---

## Advanced: Environment Variables

All exec scripts (`openclaw-engaging.sh`, `slurm-openclaw.sh`,
`slurm-gateway.sh`, `setup.sh`) support these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_SIF` | `apptainer/openclaw.sif` | Path to container image |
| `OPENCLAW_SLURM_BINDS` | off | Bind-mount SLURM commands into container |
| `OPENCLAW_CONTAINALL` | **on** | Filesystem isolation (set `0` to disable) |
| `OPENCLAW_GATEWAY_PORT` | `18790` | Gateway port (gateway scripts only) |
| `OPENCLAW_LOGIN_NODE` | `orcd-login.mit.edu` | Login node for SSH tunnel info |
| `OPENCLAW_AGENT` | `main` | Agent name (batch/gateway scripts) |
| `OPENCLAW_PROMPT` | greeting | Task prompt (batch script only) |

> **Note:** The container's `$HOME` is set to the parent of the repo
> (where you ran `git clone`). `.openclaw/` lives there automatically. See
> [Where `.openclaw` lives](#where-openclaw-lives) for details.

### SLURM access from inside the container (`OPENCLAW_SLURM_BINDS`)

Enable this to let the agent submit and manage SLURM jobs from within the
container — the agent can write batch scripts and run `sbatch` directly:

```bash
# Agent can now use sbatch, squeue, scancel, sinfo, srun, sacct
OPENCLAW_SLURM_BINDS=1 openclaw agent --local --agent main -m "Write a SLURM batch script for my analysis and submit it"

# With batch jobs
OPENCLAW_SLURM_BINDS=1 sbatch apptainer/slurm-openclaw.sh
```

This bind-mounts the host's SLURM binaries (`/usr/bin/sbatch`, etc.),
libraries (`/usr/lib64/slurm/`), config (`/etc/slurm/`), and munge
authentication socket (`/run/munge/`) into the container.

> **Security note: sandbox escape by design.** When `OPENCLAW_SLURM_BINDS=1`
> is set, the agent can submit SLURM jobs that run **outside** the Apptainer
> container — on the host, with your full user permissions. This is the
> intended behavior (the whole point is to let the agent orchestrate cluster
> jobs), but it means the container is no longer a complete security boundary.
> Jobs submitted by the agent can access any file you can access, install
> software, and consume your SLURM allocation. **Only enable this when you
> trust the agent's task and have reviewed what it plans to submit.** When
> disabled (the default), the agent is fully contained.

> **Note:** This relies on the host and container having compatible system
> libraries. If you see `sbatch` errors about missing libraries, the host
> SLURM version may be incompatible. As a fallback, the agent can write batch
> scripts and you can run `sbatch` outside the container.

### Filesystem isolation (`OPENCLAW_CONTAINALL`, default: on)

By default, all scripts pass `--containall` to Apptainer. This disables
auto-mounting of home, `/tmp`, and the current working directory — the agent
can only see the repo directory, `.openclaw/`, and `/tmp`:

```bash
# Default (containall on) — agent can't see ~/.ssh, ~/.gnupg, etc.
openclaw agent --local --agent main

# To grant access to additional directories, use APPTAINER_BIND:
APPTAINER_BIND="~/orcd/scratch/oclaw/workdata" openclaw agent --local --agent main -m "Analyze the data in ~/orcd/scratch/oclaw/workdata/"

# Disable containall (not recommended):
OPENCLAW_CONTAINALL=0 openclaw agent --local --agent main
```

The scripts automatically add `--home` and `-B /tmp` so the agent can still
access its config and scratch space. Only bind directories the agent actually
needs — avoid disabling containall entirely.

---

## Session Persistence & Resumability

This is the most important difference from a DigitalOcean droplet. SLURM
jobs are ephemeral — they get preempted, time out, or you cancel them.
OpenClaw is designed so that **nothing is lost** when this happens.

### Where state lives

```
~/orcd/scratch/oclaw/.openclaw/     # Next to the repo
├── .env                            # API key(s)
├── openclaw.json            # Config (set by onboarding wizard)
└── agents/
    └── main/
        └── sessions/
            ├── sessions.json       # Session index
            └── <session-id>.jsonl  # Conversation transcript
```

The install directory (and everything in it) is:
- **Persistent** across all SLURM jobs
- **Shared** across all Engaging nodes (NFS)
- **Private** to your user account

### What happens when a job is killed

1. The OpenClaw process exits
2. Session transcripts have been flushed to disk throughout the run
3. Next time you run the agent, it picks up where it left off

The setup script configures `session.reset.mode: "idle"` with a 1-year
timeout so sessions are effectively never discarded. On a VPS the default
daily reset makes sense, but on HPC you want conversations to survive
indefinitely across job preemptions.

### Resuming

```bash
# Same command as before — automatically resumes the last session
openclaw agent --local --agent main -m "Continue where we left off."
```

### Starting fresh

Create a new named agent for a different project:

```bash
openclaw agents add my-new-project

openclaw agent --local --agent my-new-project \
  -m "Starting a brand new analysis..."
```

---

## Reconfiguring Later

You don't need to rerun the full onboarding. Use `configure` to update
individual sections:

```bash
# Interactive menu of all config sections
openclaw configure

# Update just one section
openclaw configure --section model
openclaw configure --section channels
openclaw configure --section skills

# Health check & diagnostics
openclaw doctor

# List active sessions
openclaw sessions
```

---

## Filesystem Access & Your Data

By default, the scripts run with `--containall` (filesystem isolation on).
The agent can only see:

- The **repo directory** (`~/orcd/scratch/oclaw/openclaw-engaging/`)
- **`.openclaw/`** next to the repo (config, sessions, memory)
- **`/tmp`** (scratch)

Your home directory, `.ssh/`, `.gnupg/`, and everything else is **not
visible** to the agent by default. This is intentional — it prevents prompt
injection attacks from exfiltrating credentials.

### What's accessible by default (containall on)

| Path | Accessible? | Notes |
|------|-------------|-------|
| Repo directory | Yes | Read/write |
| `.openclaw/` next to repo | Yes | Config, sessions, credentials |
| `/tmp` | Yes | Temporary scratch |
| `~/` (home directory) | **No** | Hidden by containall |
| `~/.ssh/`, `~/.gnupg/` | **No** | Hidden by containall |

### What's NOT accessible by default

Shared lab directories, project pools, and scratch filesystems are **not**
mounted. You must bind them explicitly:

```bash
# Mount a shared lab directory
APPTAINER_BIND="/pool/lab-data" openclaw agent --local --agent main -m "Read the CSV files in /pool/lab-data/experiment-2025/"

# Mount multiple paths (comma-separated)
APPTAINER_BIND="/pool/lab-data,/scratch/$USER" openclaw agent --local --agent main -m "Compare datasets in /pool/lab-data/ with results in /scratch/$USER/"
```

### For batch jobs

Add bind mounts to the SLURM script by setting `APPTAINER_BIND`:

```bash
APPTAINER_BIND="/pool/lab-data,/scratch/$USER" sbatch apptainer/slurm-openclaw.sh
```

Or edit `slurm-openclaw.sh` to include `-B /pool/lab-data` in the
`apptainer exec` call.

> **This is the key advantage over DigitalOcean:** your research data is
> already on the cluster filesystem. Bind it into the container and the
> agent has direct access — no uploading, no copying to a separate server.
>
> **Important:** While your raw data files stay on the cluster, the agent
> sends prompts and file excerpts to cloud LLM APIs (Anthropic, OpenAI,
> etc.) over HTTPS for processing. Do not point the agent at sensitive or
> restricted data without understanding this.

---

## Comparison: DigitalOcean vs Engaging

| | DigitalOcean Droplet | MIT Engaging (this guide) |
|---|---|---|
| **Setup** | 1-Click marketplace button | `setup.sh` (build + onboard wizard) |
| **Container** | Docker | Apptainer |
| **Persistence** | Always-on VM (systemd) | Home directory (NFS) |
| **Session survival** | Automatic | Automatic |
| **Compute** | Fixed droplet size | Flexible SLURM allocation |
| **Data access** | Upload to droplet | Already on cluster |
| **Cost** | Monthly droplet fee | Free (MIT account) |
| **GPU** | Extra cost | Not needed — agent submits GPU jobs via SLURM |
| **Dashboard** | `http://<droplet-ip>:18789/` | SSH tunnel to compute node |
| **Onboarding** | Same `openclaw onboard` wizard | Same `openclaw onboard` wizard |

The key difference: on DigitalOcean the gateway runs as a persistent service.
On Engaging, you run agents on-demand via SLURM and rely on session
persistence for continuity. The setup wizard is identical.

---

## The Apptainer Recipe

The container definition (`apptainer/openclaw.def`) pulls the official Docker
image (same one used on DigitalOcean) and layers on HPC-specific additions:

- A CLI wrapper so `openclaw` works from any working directory
- **Homebrew (Linuxbrew)** — many OpenClaw skills use `brew` as their
  package manager, so it's pre-installed at build time
- Skill dependencies via `apt-get`: `ffmpeg`, `git`, `python3`, `golang`,
  `curl`, `wget`
- Additional tools: `gh` (GitHub CLI), `uv` (Python package manager),
  `himalaya` (email CLI), `gemini-cli`, `mcporter`
- Environment variables that redirect npm/pip/go installs to your home
  directory (since the SIF filesystem is read-only at runtime)

> **Note:** `openai-whisper` is not included because it pulls PyTorch + CUDA
> (~3 GB), which causes out-of-memory errors during the container build.
> If you need whisper, install it at runtime: `pip3 install --user openai-whisper`

To rebuild when upstream releases a new version:

```bash
srun --mem=8G --time=01:00:00 --cpus-per-task=2 apptainer build --force apptainer/openclaw.sif apptainer/openclaw.def
```

---

## Keeping Up with Upstream OpenClaw

This repo (`openclaw-engaging`) is a fork of the
[original OpenClaw](https://github.com/openclaw/openclaw) with Apptainer
recipes added. When the upstream project releases updates (new features,
bug fixes, model support), you can pull those in without losing any of your
Apptainer or config changes.

If you followed Step 1, you already have `upstream` configured. Verify:

```bash
git remote -v
# origin    .../openclaw-engaging.git (fetch)
# upstream  .../openclaw.git (fetch)
```

If `upstream` is missing, add it:

```bash
git remote add upstream https://github.com/openclaw/openclaw.git
```

### Pull in upstream updates

```bash
git fetch upstream
git merge upstream/main
# Resolve any conflicts if prompted, then:
git push origin main
```

The Apptainer files (`apptainer/`, `docs/engaging-apptainer-guide.md`) don't
exist in upstream, so merges are almost always conflict-free.

### Rebuild the container after updating

Upstream updates change the Docker image that the container is built from.
After merging, rebuild to pick up the latest OpenClaw version:

```bash
module load apptainer/1.4.2
srun --mem=8G --time=01:00:00 --cpus-per-task=2 apptainer build --force apptainer/openclaw.sif apptainer/openclaw.def
```

Your `~/.openclaw/` config and sessions are unaffected — only the container
image changes.

### Automated updates with `update.sh`

Instead of running the manual steps above, you can use the `update.sh` script
to handle the full cycle — fetch, merge, and rebuild — in one command:

```bash
cd ~/orcd/scratch/oclaw/openclaw-engaging
./apptainer/update.sh
```

The script will:
1. Add the `upstream` remote if it's missing
2. Fetch upstream and show how many new commits are available
3. Merge `upstream/main` (aborts cleanly if there are conflicts)
4. Prompt you to rebuild the container via `srun`
5. Print the new OpenClaw version after the build

To **check for updates without applying them**:

```bash
./apptainer/update.sh --check
```

This prints a one-line notice if updates are available, or nothing if you're
already up to date. Both `start-gateway.sh` and `setup.sh` run this
automatically — so you'll always see a reminder when upstream has new commits.

---

## Troubleshooting

### "apptainer: command not found"

```bash
module load apptainer/1.4.2
# Find available versions: module spider apptainer
```

### Container build fails with "Failed to create thread"

Login nodes restrict process counts. Always build on a compute node:

```bash
srun --mem=8G --time=01:00:00 --cpus-per-task=2 apptainer build apptainer/openclaw.sif apptainer/openclaw.def
```

### Container build OOM killed

The build needs at least 8 GB. If mksquashfs is killed:

```bash
srun --mem=8G --time=01:00:00 --cpus-per-task=2 apptainer build apptainer/openclaw.sif apptainer/openclaw.def
```

### Container build fails (disk space)

```bash
df -h ~
# If /tmp is full:
export APPTAINER_TMPDIR=$HOME/tmp && mkdir -p $APPTAINER_TMPDIR
```

### Gateway OOM killed

The gateway needs more than 1 GB. The default in `slurm-gateway.sh` is 4 GB.
If you still see OOM errors, increase `--mem` in the script.

### Dashboard shows "gateway token missing"

The dashboard URL must include your auth token. Check the gateway job output
for the full URL:

```bash
cat openclaw-gw-<jobid>.out
```

The URL should look like `http://localhost:18790/?token=abc123...`. If you
opened the dashboard without the token, paste it in the Control UI settings.

You can also find your token directly:

```bash
python3 -c "import json; print(json.load(open('.openclaw/openclaw.json'))['gateway']['auth']['token'])"
```

### Dashboard shows "pairing required"

The gateway requires device pairing for non-local connections. Since you
connect through an SSH tunnel, the gateway sees a remote IP. The fix is to
disable device auth for the Control UI (token auth still protects access):

```bash
openclaw config set gateway.controlUi.dangerouslyDisableDeviceAuth true
```

Then restart the gateway: `scancel <jobid> && cd ~/orcd/scratch/oclaw/openclaw-engaging && sbatch apptainer/slurm-gateway.sh`

The `setup.sh` script pre-configures this automatically.

### Token not auto-filling from URL / "Device Identity Required"

Some browsers (especially when the gateway is first accessed) may not auto-fill
the token from the URL query parameter. You may see `OPENCLAW_GATEWAY_TOKEN
(optional)` in the token field, or a "Device Identity Required" prompt, even
after clicking the tokenized URL.

**To fix this:**

1. Copy the token value from the URL — it's the string after `?token=`:
   ```
   http://localhost:18790/?token=abc123def456...
                                 ^^^^^^^^^^^^^^ copy this part
   ```

2. Paste it into the token input field on the dashboard and submit.

3. If you still see "Device Identity Required", make sure device auth is
   disabled:
   ```bash
   openclaw config set gateway.controlUi.dangerouslyDisableDeviceAuth true
   ```
   Then restart the gateway (`scancel <jobid>` and relaunch).

4. If the token field doesn't appear at all, try opening the URL in a private /
   incognito window, or append `/?token=<your-token>` manually to
   `http://localhost:18790/`.

**Finding your token** if you've lost it (run from `~/orcd/scratch/oclaw/`):
```bash
python3 -c "import json; print(json.load(open('.openclaw/openclaw.json'))['gateway']['auth']['token'])"
```

### SSH tunnel "Connection refused"

- Make sure the gateway job is still running: `squeue -u $USER`
- Make sure you're tunneling to the **compute node** (e.g., `node1234`), not
  the login node
- Make sure the port matches (default: `18790`)

### Sandbox / Docker errors from the agent

Disable sandboxing — Docker-in-Docker doesn't work inside Apptainer:

```bash
openclaw config set agents.defaults.sandbox.mode off
```

The `setup.sh` script does this automatically.

### API connection errors

Engaging compute nodes have outbound internet. Verify:

```bash
srun --pty bash -c "curl -sI https://api.anthropic.com"
```

### API key not found

- Rerun the wizard: `openclaw configure --section model`
- Or check: `cat .openclaw/.env`  (from the parent of the repo)
- Or pass explicitly: `ANTHROPIC_API_KEY=sk-ant-... sbatch apptainer/slurm-openclaw.sh`

### Node.js or module errors

The container bundles Node.js 22 and all dependencies. If you see module
errors, rebuild the container.

---

## Share with Your Lab

The `.sif` file is a single read-only image that anyone can use. Copy it to
a shared directory:

```bash
cp apptainer/openclaw.sif /pool/shared-lab/openclaw.sif
```

Each user clones the repo and runs `setup.sh` to set up their personal config
in their own `.openclaw/` directory. One container image, many users, isolated state.

---

## Agent Identity & Cluster Knowledge

OpenClaw agents load **workspace files** (`TOOLS.md`, `SOUL.md`, `IDENTITY.md`)
at the start of every session. These files are the agent's memory and identity —
the equivalent of a DigitalOcean droplet's MOTD that tells the agent about its
environment.

### What the init script does

`setup.sh` automatically runs `orcd-workspace-init.sh` after onboarding. This
populates the workspace with cluster-specific context:

| File | Content |
|------|---------|
| `TOOLS.md` | Storage paths, SLURM partitions, module system, OpenClaw commands, ORCD doc links |
| `SOUL.md` | Appends "HPC co-scientist" framing — the agent knows it's on Engaging in an Apptainer container |
| `IDENTITY.md` | Left as-is (already customized during first agent session) |

### Running it manually

```bash
# Standalone (idempotent — safe to rerun)
./apptainer/orcd-workspace-init.sh

# Force overwrite existing TOOLS.md
FORCE=1 ./apptainer/orcd-workspace-init.sh
```

### Customizing

Edit the workspace files directly — they live at `.openclaw/workspace/`
next to the repo:

```bash
# Add your own tools/paths (from the parent of the repo)
vim .openclaw/workspace/TOOLS.md

# Change the agent's personality
vim .openclaw/workspace/SOUL.md
```

The init script won't overwrite files that contain custom content (unless you
use `FORCE=1`). It only replaces default templates.

### Verifying

Ask the agent about its environment:

```bash
openclaw agent --local --agent main -m "What cluster am I on?"
```

It should reference MIT Engaging, SLURM, ORCD storage paths, etc.

---

## Important Notes

### Responsible use and data privacy

> **Use only low-risk data.** The agent sends prompts and file excerpts to
> cloud LLM APIs (Anthropic, OpenAI, etc.) over HTTPS. Your raw data files
> stay on the cluster, but any content the agent reads will be transmitted
> to your chosen LLM provider. Do not point the agent at restricted,
> sensitive, or export-controlled datasets. See
> [MIT IS&T data classification](https://ist.mit.edu/security/data-classification)
> for guidance.

- **You are responsible for the actions of your agent.** Be sure you and any
  of your agents follow the [Acceptable Use and Code of Conduct](https://orcd-docs.mit.edu/code-of-conduct/).
- Only grant the agent access to directories it needs (use `APPTAINER_BIND`
  for explicit bind mounts rather than disabling containall)
- Review third-party skills before enabling them — skills can execute
  arbitrary code with your permissions
- Monitor your API usage; some providers have suspended accounts for
  very high automated usage through agent platforms
- If you enable `OPENCLAW_SLURM_BINDS=1`, the agent can submit SLURM jobs
  that run outside the container with your full user permissions — this is
  an intentional sandbox escape. See
  [SLURM access from inside the container](#slurm-access-from-inside-the-container-openclaw_slurm_binds)
  for details

### Sandbox is disabled — by design

The setup script sets `agents.defaults.sandbox.mode: "off"`. This is
intentional: the agent needs to run commands and edit files to be useful.
On a regular machine, OpenClaw uses Docker containers as a sandbox. On
Engaging, Docker isn't available — **Apptainer is the security boundary
instead**.

By default, all scripts enable `--containall`. The container filesystem is
read-only; the agent can access its config and repo but **not** your home
directory, `.ssh/`, or other sensitive paths. This is the primary security
boundary — the agent cannot modify the host OS, install system packages, or
affect other users.

To grant the agent access to additional directories, use `APPTAINER_BIND`:

```bash
# Give the agent access to a specific data directory
APPTAINER_BIND="~/orcd/scratch/oclaw/workdata" \
  openclaw agent --local --agent main \
  -m "Analyze the data in ~/orcd/scratch/oclaw/workdata/"
```

Or manually with `apptainer exec`:

```bash
apptainer exec --containall \
  --home ~/orcd/scratch/oclaw \
  -B /tmp \
  -B ~/orcd/scratch/oclaw/workdata \
  apptainer/openclaw.sif openclaw agent --local --agent main
```

To disable containall entirely (not recommended):

```bash
OPENCLAW_CONTAINALL=0 openclaw agent --local --agent main
```

See [Filesystem isolation](#filesystem-isolation-openclaw_containall-default-on) for details.

### Where `.openclaw` lives

All scripts set the container's `$HOME` to the **parent directory** of
the repo. This means `.openclaw/` lives next to the repo, in whatever
directory you cloned `openclaw-engaging` into:

```
~/orcd/scratch/oclaw/                  # container $HOME (parent of repo)
├── openclaw-engaging/                 # the repo
│   ├── apptainer/
│   ├── docs/
│   └── ...
└── .openclaw/                         # ← config, sessions, memory
    ├── openclaw.json
    ├── agents/
    └── workspace/
```

**Your clone location determines where state lives.** If you clone to
`~/orcd/scratch/openclaw-engaging`, then `.openclaw/` will be at
`~/orcd/scratch/.openclaw/`. No extra flags or configuration needed.

**To avoid home directory quota issues**, clone to scratch from the start:

```bash
cd ~/orcd/scratch
git clone https://github.com/qsimeon/openclaw-engaging.git
cd openclaw-engaging
```

> **Note:** Scratch may be purged after ~90 days of inactivity. If using
> scratch, back up `.openclaw/` periodically (especially `openclaw.json`
> and `credentials/`). PI/group storage is not auto-purged.

---

## Next Steps

- **Multiple agents**: `openclaw agents add <name>` — isolate per-project
- **Tools & skills**: Web search, file I/O, browser automation, custom skills
- **Memory**: Persistent knowledge with SQLite + vector search
- **Channels**: Telegram, Discord, Slack (needs a long-running gateway job)

Full documentation: [docs.openclaw.ai](https://docs.openclaw.ai) |
[GitHub](https://github.com/openclaw/openclaw)
