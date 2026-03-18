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
│  ~/your-data/  ◄── auto-mounted             │
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
- Minimal resources: ~1 GB RAM, 1 CPU, no GPU, any partition

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

## Step 1: Clone and Build

SSH into Engaging and clone the repo:

```bash
ssh <username>@orcd-login.mit.edu
git clone https://github.com/qsimeon/openclaw-engaging.git
cd openclaw-engaging
```

> **Tip:** All scripts set the container's `$HOME` to the parent of the repo,
> so all OpenClaw state (`.openclaw/`) lives next to the repo — not deep
> inside it. If your home quota is tight, clone to scratch instead:
> `cd ~/orcd/scratch && git clone ...`

Add the upstream remote so you can pull future OpenClaw updates:

```bash
git remote add upstream https://github.com/openclaw/openclaw.git
```

Verify your remotes:

```bash
git remote -v
# origin    https://github.com/qsimeon/openclaw-engaging.git (fetch)
# upstream  https://github.com/openclaw/openclaw.git (fetch)
```

Now build the container:

```bash
# Load Apptainer
module load apptainer/1.4.2

# Build the container on a compute node (~10 minutes)
# Login nodes hit process limits — always use srun for builds
srun --mem=8G --time=01:00:00 --cpus-per-task=2 \
  apptainer build apptainer/openclaw.sif apptainer/openclaw.def
```

This pulls the same Docker image used by DigitalOcean and packages it as an
Apptainer `.sif` file.

Verify:

```bash
apptainer exec apptainer/openclaw.sif openclaw --version
```

---

## Step 2: Run the Setup Wizard

This is the Engaging equivalent of DigitalOcean's 1-Click Deploy. The
OpenClaw onboarding wizard walks you through everything interactively.

### Option A: Automated 1-Click Script (recommended)

The setup script builds the container (if needed), pre-configures HPC
settings, and launches the wizard — all in one go:

```bash
chmod +x apptainer/setup.sh

# Run everything on a compute node (needs --pty for the wizard)
srun --pty --mem=8G --time=01:00:00 --cpus-per-task=2 ./apptainer/setup.sh
```

Or split it if you already built the container in Step 1:

```bash
# Onboard only (interactive wizard, container must already exist)
srun --pty --mem=4G --time=00:30:00 ./apptainer/setup.sh --onboard-only
```

The setup script automatically checks for upstream OpenClaw updates before
building (and offers to merge them), then configures HPC-specific settings
before launching the wizard:

- **Sandbox: off** — disables Docker-in-Docker sandboxing (not available
  inside Apptainer). Without this, the agent can't run shell commands or
  access your files.
- **Session idle timeout: 1 year** — effectively disables auto-reset so
  sessions survive job preemption and cluster maintenance.
- **Gateway: LAN bind, port 18790, device auth disabled** — the gateway
  binds to all interfaces so it's reachable via SSH tunnel, and device
  pairing is disabled since the SSH tunnel itself provides security.

### Option B: Manual steps

```bash
# Get an interactive compute node (the wizard needs a terminal)
srun --pty --mem=1G --time=00:30:00 bash

# Load Apptainer on the compute node
module load apptainer/1.4.2

# Launch the onboarding wizard
apptainer exec apptainer/openclaw.sif openclaw onboard --skip-daemon
```

If you use Option B, also disable sandboxing:

```bash
openclaw config set agents.defaults.sandbox.mode off
```

### What the wizard covers

1. **LLM provider** — pick Anthropic, OpenAI, OpenRouter, or others
2. **API key** — paste your key (stored securely in `~/.openclaw/.env`)
3. **Model selection** — choose your default model
4. **Channels** (optional) — connect Telegram, Discord, Slack, etc.
5. **Skills** (optional) — enable web search, file tools, and more

> **Why `--skip-daemon`?** On DigitalOcean, OpenClaw installs a systemd
> service so the gateway runs 24/7. Engaging doesn't have systemd on compute
> nodes, so we skip that. Instead, you run agents on-demand through SLURM,
> and sessions persist on your home directory between runs.

> **Skill install failures are normal.** Some skills require Homebrew taps
> that can't be installed inside the read-only container. You'll see
> "brew not installed" errors — **this is fine**. The core agent and most
> skills (web search, file tools, code execution, etc.) work regardless.
> You can install missing skill dependencies later in your home directory.

> **Health check "SECURITY ERROR" about ws://.** The wizard warns that the
> gateway uses plaintext `ws://` on a non-loopback address. This is expected
> — on Engaging you connect via an encrypted SSH tunnel, so the traffic is
> secure. You can safely ignore this warning.

---

## Step 3: The `openclaw` Command

On DigitalOcean, OpenClaw is installed globally via npm so you just type
`openclaw ...`. On Engaging, the app lives inside a read-only Apptainer
container, so normally you'd need `apptainer exec apptainer/openclaw.sif
openclaw ...` every time.

The `setup.sh` script eliminates this by adding an `openclaw` alias to your
`~/.bashrc`. After setup, activate it:

```bash
source ~/.bashrc
```

Now you can use `openclaw` directly — it handles module loading and container
paths for you:

```bash
openclaw --help          # same output as DigitalOcean
openclaw --version
openclaw configure
openclaw doctor
openclaw sessions
```

> If the alias wasn't installed (e.g., you used Option B), add it manually:
> ```bash
> echo "alias openclaw='~/openclaw-engaging/apptainer/openclaw-engaging.sh'" >> ~/.bashrc
> source ~/.bashrc
> ```

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
openclaw agent --local --agent main \
  -m "I have CSV files in ~/my-project/data/. Help me explore them."
```

### Batch job (unattended)

```bash
cd ~/openclaw-engaging
OPENCLAW_PROMPT="Summarize all CSV files in ~/my-project/data/" \
  sbatch apptainer/slurm-openclaw.sh
```

Output goes to `openclaw-<jobid>.out`.

### Binding extra directories

Apptainer auto-mounts your home directory. If your data lives elsewhere:

```bash
apptainer exec -B /pool/lab-data:/data apptainer/openclaw.sif \
  openclaw agent --local --agent main \
  -m "Analyze the datasets in /data/"
```

---

## Step 5: Gateway & Dashboard (Browser Access)

The gateway is a long-running server that serves the web dashboard and
processes messages from connected channels (Telegram, Discord, etc.). On
DigitalOcean it runs as a systemd service and you access it directly at
`http://<droplet-ip>:18789/`. On Engaging, you run it as a SLURM job and
reach it from your laptop via SSH tunnel.

### Start the gateway

The launcher submits the SLURM job, waits for it to start, and prints the
connection info automatically — no need to hunt for output files:

```bash
cd ~/openclaw-engaging
./apptainer/start-gateway.sh
```

If a gateway is already running, it shows the existing connection info
instead of starting a second one.

> **Manual alternative:** `sbatch apptainer/slurm-gateway.sh` then
> `cat openclaw-gw-<jobid>.out` to see the connection info.

You'll see output like:

```
  1) SSH tunnel (run on your laptop — kills any old tunnel first):

     lsof -ti:18790 | xargs kill -9 2>/dev/null; autossh -M 0 -f -N -L 18790:node1234:18790 <user>@<login-node>

  2) Open in your browser:

     http://localhost:18790/?token=abc123...
```

### Connect from your laptop

**a) Open the SSH tunnel.** On your local machine, run the tunnel command
from the output:

```bash
lsof -ti:18790 | xargs kill -9 2>/dev/null; autossh -M 0 -f -N -L 18790:<node>:18790 <username>@<login-node>
```

The `lsof ... | xargs kill` prefix clears any stale tunnel on that port
first — autossh silently fails if the port is already occupied. The whole
line is safe to copy-paste every time.

| Placeholder | Replace with |
|---|---|
| `<node>` | Compute node from the output (e.g., `node3311`) |
| `<username>` | Your Engaging username |
| `<login-node>` | Your login host (e.g., `eofe10.mit.edu` or `orcd-login.mit.edu`) |

`autossh` automatically reconnects the tunnel if your laptop sleeps or the
connection drops. `-M 0` **must come first** — it tells autossh to rely on
SSH keepalive instead of a monitoring port.

Install autossh once: `brew install autossh` (Mac) or `apt install autossh`
(Linux).

Also add these to your `~/.ssh/config` so SSH detects dead connections:

```
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

> **If you don't have autossh**, use plain ssh:
> `lsof -ti:18790 | xargs kill -9 2>/dev/null; ssh -f -N -L 18790:<node>:18790 <username>@<login-node>`
> You'll just need to re-run if the tunnel drops after laptop sleep.

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
| `OPENCLAW_CONTAINALL` | off | Strict filesystem isolation |
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
OPENCLAW_SLURM_BINDS=1 openclaw agent --local --agent main \
  -m "Write a SLURM batch script for my analysis and submit it"

# With batch jobs
OPENCLAW_SLURM_BINDS=1 sbatch apptainer/slurm-openclaw.sh
```

This bind-mounts the host's SLURM binaries (`/usr/bin/sbatch`, etc.),
libraries (`/usr/lib64/slurm/`), config (`/etc/slurm/`), and munge
authentication socket (`/run/munge/`) into the container.

> **Note:** This relies on the host and container having compatible system
> libraries. If you see `sbatch` errors about missing libraries, the host
> SLURM version may be incompatible. As a fallback, the agent can write batch
> scripts and you can run `sbatch` outside the container.

### Strict isolation (`OPENCLAW_CONTAINALL`)

For maximum filesystem isolation, set `OPENCLAW_CONTAINALL=1`. This passes
`--containall` to Apptainer, which disables auto-mounting of home, `/tmp`,
and the current working directory:

```bash
OPENCLAW_CONTAINALL=1 openclaw agent --local --agent main
```

The scripts automatically add `--home` and `-B /tmp` so the agent can still
access its config and scratch space. To grant access to additional directories,
use `APPTAINER_BIND`:

```bash
OPENCLAW_CONTAINALL=1 APPTAINER_BIND="~/my-project" \
  openclaw agent --local --agent main \
  -m "Analyze the data in ~/my-project/"
```

---

## Session Persistence & Resumability

This is the most important difference from a DigitalOcean droplet. SLURM
jobs are ephemeral — they get preempted, time out, or you cancel them.
OpenClaw is designed so that **nothing is lost** when this happens.

### Where state lives

```
<install-dir>/.openclaw/     # Next to the repo (e.g., ~/.openclaw/)
├── .env                     # API key(s)
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

Apptainer **automatically mounts your home directory** into the container.
This means the agent can read and write files in `~/` just like a regular
process.

### What's accessible by default

| Path | Mounted? | Notes |
|------|----------|-------|
| `~/` (home directory) | Yes, auto-mounted | Read/write. Where `~/.openclaw/` state lives |
| `/tmp` | Yes, auto-mounted | Temporary scratch space |
| Current working directory | Yes, auto-mounted | Whatever directory you run `apptainer exec` from |

### What's NOT accessible by default

Shared lab directories, project pools, and scratch filesystems outside your
home are **not** mounted automatically. You must bind them explicitly:

```bash
# Mount a shared lab directory
apptainer exec -B /pool/lab-data apptainer/openclaw.sif \
  openclaw agent --local --agent main \
  -m "Read the CSV files in /pool/lab-data/experiment-2025/"

# Mount multiple paths
apptainer exec \
  -B /pool/lab-data \
  -B /scratch/$USER \
  apptainer/openclaw.sif \
  openclaw agent --local --agent main \
  -m "Compare datasets in /pool/lab-data/ with results in /scratch/$USER/"

# Mount with a custom path inside the container
apptainer exec -B /nfs/shared/project42:/data apptainer/openclaw.sif \
  openclaw agent --local --agent main \
  -m "Analyze everything in /data/"
```

### For batch jobs

Add bind mounts to the SLURM script by setting `APPTAINER_BIND`:

```bash
APPTAINER_BIND="/pool/lab-data,/scratch/$USER" \
  sbatch apptainer/slurm-openclaw.sh
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
| **GPU** | Extra cost | Available via `--gres` |
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
srun --mem=8G --time=01:00:00 --cpus-per-task=2 \
  apptainer build --force apptainer/openclaw.sif apptainer/openclaw.def
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
srun --mem=8G --time=01:00:00 --cpus-per-task=2 \
  apptainer build --force apptainer/openclaw.sif apptainer/openclaw.def
```

Your `~/.openclaw/` config and sessions are unaffected — only the container
image changes.

### Automated updates with `update.sh`

Instead of running the manual steps above, you can use the `update.sh` script
to handle the full cycle — fetch, merge, and rebuild — in one command:

```bash
cd ~/openclaw-engaging
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
The `setup.sh` script goes further: it offers to merge updates before building
the container, ensuring new users always start with the latest version.

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
srun --mem=8G --time=01:00:00 --cpus-per-task=2 \
  apptainer build apptainer/openclaw.sif apptainer/openclaw.def
```

### Container build OOM killed

The build needs at least 8 GB. If mksquashfs is killed:

```bash
srun --mem=8G --time=01:00:00 --cpus-per-task=2 \
  apptainer build apptainer/openclaw.sif apptainer/openclaw.def
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

Then restart the gateway: `scancel <jobid> && cd ~/openclaw-engaging && sbatch apptainer/slurm-gateway.sh`

The `setup.sh` script pre-configures this automatically.

### Token not auto-filling from URL

The dashboard may not auto-fill the token from the URL query parameter. If you
see `OPENCLAW_GATEWAY_TOKEN (optional)` in the token field after clicking the
tokenized URL, copy the token value from the URL and paste it manually.

The token is the string after `?token=` in the URL, e.g.:
```
http://localhost:18790/?token=abc123...
                              ^^^^^^^^^ copy this part
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

## Running Multiple Agents in Parallel

You can launch multiple independent gateway instances simultaneously — useful
for class demos, parallel experiments, or giving each team member their own
dashboard.

### Architecture

Each instance is a fully independent stack:

```
┌─ Your laptop ─────────────────────────────────────────────┐
│                                                           │
│  Browser tab 1 → http://localhost:18790/?token=...        │
│  Browser tab 2 → http://localhost:18791/?token=...        │
│  Browser tab 3 → http://localhost:18792/?token=...        │
│           │              │              │                  │
│           └──── SSH tunnel (one or multiple) ─────┐       │
└───────────────────────────────────────────────────┼───────┘
                                                    │
┌─ Engaging cluster ────────────────────────────────┼───────┐
│                                                   │       │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┴─┐    │
│  │ SLURM job 1  │  │ SLURM job 2  │  │ SLURM job 3  │    │
│  │ port 18790   │  │ port 18791   │  │ port 18792   │    │
│  │ agent-1      │  │ agent-2      │  │ agent-3      │    │
│  └──────────────┘  └──────────────┘  └──────────────┘    │
│                                                           │
│  Shared: ~/.openclaw/ config, NFS home directory          │
└───────────────────────────────────────────────────────────┘
```

### Quick start

```bash
# Launch 3 independent instances
./apptainer/start-multi.sh 3

# Or with custom names (e.g., for a class)
./apptainer/start-multi.sh 3 --prefix demo
# → demo-1 on :18790, demo-2 on :18791, demo-3 on :18792
```

The script prints a summary table with job IDs, nodes, ports, SSH tunnel
commands, and dashboard URLs — designed for easy copy-paste.

### SSH tunnels

The output includes a single combined tunnel command for all instances:

```bash
autossh -M 0 -f -N -L 18790:node1:18790 -L 18791:node2:18791 user@orcd-login.mit.edu
```

Or you can open per-instance tunnels separately.

### Cleanup

```bash
# Stop all instances (job IDs shown in the summary)
scancel JOB_ID_1 JOB_ID_2 JOB_ID_3

# Or cancel all your gateway jobs at once
scancel -u $USER -n openclaw-gw-1
scancel -u $USER -n openclaw-gw-2
scancel -u $USER -n openclaw-gw-3
```

### Alternative: shared gateway with multiple agents

For advanced users, you can also run a single gateway that routes to multiple
named agents:

```bash
# Create named agents
openclaw agents add project-a
openclaw agents add project-b

# One gateway serves all agents (switch in the dashboard)
./apptainer/start-gateway.sh
```

This uses fewer SLURM resources but all agents share one gateway process.

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

- Only grant the agent access to directories it needs (use explicit
  `-B /path` bind mounts rather than mounting everything)
- Review third-party skills before enabling them — skills can execute
  arbitrary code with your permissions
- Monitor your API usage; some providers have suspended accounts for
  very high automated usage through agent platforms

### Sandbox is disabled — by design

The setup script sets `agents.defaults.sandbox.mode: "off"`. This is
intentional: the agent needs to run commands and edit files to be useful.
On a regular machine, OpenClaw uses Docker containers as a sandbox. On
Engaging, Docker isn't available — **Apptainer is the security boundary
instead**.

By default, Apptainer auto-mounts your home directory and current working
directory into the container. The container filesystem itself is read-only.
This gives you a practical level of isolation: the agent can access your
files but cannot modify the host OS, install system packages, or affect
other users.

**For stricter isolation**, set `OPENCLAW_CONTAINALL=1` to enable
`--containall` mode, which prevents auto-mounting and gives you full control
over what the agent can see:

```bash
# All scripts support this — home and /tmp are auto-bound
OPENCLAW_CONTAINALL=1 openclaw agent --local --agent main

# Add extra directories via APPTAINER_BIND
OPENCLAW_CONTAINALL=1 APPTAINER_BIND="~/my-project" \
  openclaw agent --local --agent main \
  -m "Analyze the data in ~/my-project/"
```

Or manually with `apptainer exec`:

```bash
apptainer exec --containall \
  --home $(pwd) \
  -B /tmp \
  -B ~/my-project \
  apptainer/openclaw.sif openclaw agent --local --agent main
```

This is useful if you want the agent to only access specific directories.
See [Strict isolation](#strict-isolation-openclaw_containall) for details.

### Where `.openclaw` lives

All scripts set the container's `$HOME` to the **parent directory** of
the repo. This means `.openclaw/` lives next to the repo, in whatever
directory you cloned `openclaw-engaging` into:

```
~/                             # cloned to ~/openclaw-engaging
├── openclaw-engaging/         # the repo
│   ├── apptainer/
│   ├── docs/
│   └── ...
└── .openclaw/                 # ← config, sessions, memory
    ├── .env
    ├── openclaw.json
    └── agents/
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
- **Parallel instances**: `./apptainer/start-multi.sh N` — independent dashboards
- **Tools & skills**: Web search, file I/O, browser automation, custom skills
- **Memory**: Persistent knowledge with SQLite + vector search
- **Channels**: Telegram, Discord, Slack (needs a long-running gateway job)

Full documentation: [docs.openclaw.ai](https://docs.openclaw.ai) |
[GitHub](https://github.com/openclaw/openclaw)
