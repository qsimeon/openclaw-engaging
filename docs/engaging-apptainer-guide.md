# Running OpenClaw on MIT Engaging with Apptainer

> **TL;DR** — Build one container, set one API key, launch AI agents on your
> scientific data using the Engaging cluster's compute. Sessions persist on your
> home directory, so you can resume exactly where you left off even after jobs
> are preempted or killed.

## Why OpenClaw on Engaging?

[OpenClaw](https://github.com/openclaw/openclaw) is an open-source AI assistant
platform — the same stack behind the
[DigitalOcean 1-Click Deploy](https://www.digitalocean.com/community/tutorials/moltbot-quickstart-guide)
and the [Docker quick-start](https://docs.openclaw.ai/install/docker). It
connects to cloud LLM providers (Anthropic Claude, OpenAI GPT-4o, Google
Gemini, OpenRouter, etc.) and gives you multi-turn conversations, tool use,
persistent memory, and multi-channel messaging — all from a single container.

On DigitalOcean you get a persistent droplet. On Engaging you get something
better: **access to shared compute resources and your research data**, without
needing to move anything off-cluster. Because OpenClaw only needs outbound
HTTPS (no GPU), it runs happily on any partition.

**What this enables for MIT staff and researchers:**

- Launch AI agents that can read and reason over your scientific data on the
  cluster filesystem
- Run long-running analysis jobs as SLURM batch submissions
- Use interactive sessions during office hours, then submit batch jobs overnight
- All conversation history and agent state lives on your home directory —
  survives job preemption, node failures, and cluster maintenance
- Share a single container image across your lab; each user's state is isolated
  in their own `~/.openclaw/`

This guide mirrors the simplicity of the DigitalOcean setup but adapted for
Engaging's SLURM + Apptainer environment.

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
│  ~/.openclaw/  ◄──────────────┘  (state)     │
│  ~/your-data/  ◄── bound into container      │
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
- Your **home directory** is auto-mounted — `~/.openclaw/` stores all config,
  sessions, and memory (persistent across jobs)
- The agent makes **outbound HTTPS calls** to your chosen LLM provider
- No GPU needed, minimal memory (~1 GB), runs on any partition

---

## Prerequisites

1. **An MIT Engaging account** — [request one here](https://engaging-web.mit.edu/)
2. **An API key** from one of these providers:
   - [Anthropic](https://console.anthropic.com/) — recommended for Claude
     models (`sk-ant-...`)
   - [OpenRouter](https://openrouter.ai/) — one key, many models (`sk-or-...`)
   - [OpenAI](https://platform.openai.com/) — GPT-4o and friends (`sk-...`)
3. **Basic comfort with the terminal** and SLURM (`srun`, `sbatch`)

---

## Step 1: Build the Container (~5 minutes)

SSH into Engaging and run:

```bash
# Clone the repo
git clone https://github.com/openclaw/openclaw.git
cd openclaw

# Load Apptainer
module load apptainer/1.4.2

# Build the container on a compute node
# (Login nodes hit process limits — always use srun for builds)
srun --mem=4G --time=00:30:00 --cpus-per-task=2 \
  apptainer build apptainer/openclaw.sif apptainer/openclaw.def
```

This pulls the published Docker image from GitHub Container Registry and
packages it as an Apptainer `.sif` file. The resulting image is ~500 MB.

> **Tip:** If disk space is tight, you can set an alternate temp directory:
> ```bash
> export APPTAINER_TMPDIR=$HOME/tmp && mkdir -p $APPTAINER_TMPDIR
> ```

Verify the build:

```bash
apptainer exec apptainer/openclaw.sif openclaw --version
```

### Automated Alternative

The helper script builds the container *and* walks you through config:

```bash
chmod +x apptainer/setup.sh
srun --mem=4G --time=00:30:00 --cpus-per-task=2 ./apptainer/setup.sh
```

---

## Step 2: Configure Your Agent (~2 minutes)

### Set your API key

```bash
mkdir -p ~/.openclaw

# Pick ONE of these — whichever provider you use:
echo 'ANTHROPIC_API_KEY=sk-ant-YOUR-KEY-HERE' > ~/.openclaw/.env
# echo 'OPENROUTER_API_KEY=sk-or-YOUR-KEY-HERE' > ~/.openclaw/.env
# echo 'OPENAI_API_KEY=sk-YOUR-KEY-HERE' > ~/.openclaw/.env

# Protect the file
chmod 600 ~/.openclaw/.env
```

### Create a config file

```bash
cat > ~/.openclaw/openclaw.json << 'EOF'
{
  "agents": {
    "defaults": {
      "model": "anthropic/claude-sonnet-4-20250514"
    }
  },
  "session": {
    "reset": {
      "mode": "never"
    }
  }
}
EOF
```

> **Key detail:** We set `session.reset.mode` to `"never"` so sessions are
> never automatically discarded. On a VPS or DigitalOcean droplet the default
> 30-minute idle timeout makes sense, but on HPC where jobs get preempted,
> you want your conversation to survive indefinitely. You can always start a
> fresh session explicitly when you want one.

### Choosing a model

| Provider   | Env variable         | Example model                          |
|------------|---------------------|----------------------------------------|
| Anthropic  | `ANTHROPIC_API_KEY` | `anthropic/claude-sonnet-4-20250514`   |
| OpenRouter | `OPENROUTER_API_KEY`| `anthropic/claude-sonnet-4-20250514`   |
| OpenAI     | `OPENAI_API_KEY`    | `openai/gpt-4o`                        |

Update the `model` in `openclaw.json` to match your provider.

---

## Step 3: Test It — Your First Query

```bash
module load apptainer/1.4.2

apptainer exec apptainer/openclaw.sif \
  openclaw agent --local --agent main \
  -m "Hello from Engaging! What can you help me with?"
```

If you see a response from the model, everything is working. The `--local`
flag runs the agent directly (no gateway server needed).

---

## Step 4: Interactive Sessions

For exploratory work — chatting with the agent about your data, asking
follow-up questions, iterating on analysis:

```bash
# Get an interactive compute node
srun --pty --mem=1G --time=02:00:00 bash

# On the compute node:
module load apptainer/1.4.2

# Start an interactive agent session
apptainer exec apptainer/openclaw.sif \
  openclaw agent --local --agent main \
  -m "I have CSV files in ~/my-project/data/. Help me explore them."
```

### Binding extra directories

By default Apptainer mounts your home directory. If your data lives elsewhere
(e.g., a shared lab directory), bind it in:

```bash
apptainer exec -B /pool/lab-data:/data apptainer/openclaw.sif \
  openclaw agent --local --agent main \
  -m "Analyze the datasets in /data/"
```

---

## Step 5: Batch Jobs

For longer-running agent tasks, submit a SLURM batch job:

```bash
# Set your API key (if not in ~/.openclaw/.env)
export ANTHROPIC_API_KEY="sk-ant-your-key-here"

# Default prompt
sbatch apptainer/slurm-openclaw.sh

# Custom prompt
OPENCLAW_PROMPT="Summarize all CSV files in ~/my-project/data/" \
  sbatch apptainer/slurm-openclaw.sh
```

Output goes to `openclaw-<jobid>.out`. The included SLURM script
(`apptainer/slurm-openclaw.sh`) requests 1 GB of memory and 1 hour.

---

## Session Persistence & Resumability

This is the most important section for HPC use. Unlike a DigitalOcean droplet
where the bot runs 24/7, SLURM jobs are ephemeral — they get preempted,
time out, or you cancel them. OpenClaw is designed so that **none of your
conversation state is lost** when this happens.

### Where state lives

```
~/.openclaw/
├── .env                              # Your API key (never in the container)
├── openclaw.json                     # Agent config
└── agents/
    └── main/
        └── sessions/
            ├── sessions.json         # Session index (metadata)
            └── <session-id>.jsonl    # Full conversation transcript
```

All of this is on your **home directory**, which is:
- Persistent across SLURM jobs
- Shared across all Engaging nodes (NFS)
- Backed up by MIT IS&T
- Private to your user account

### What happens when a job is killed

1. The OpenClaw process exits
2. The session transcript (`.jsonl`) has been flushed to disk throughout the run
3. The session index (`sessions.json`) records the last state
4. **Nothing is lost** — next time you run the agent with the same `--agent`,
   it picks up where it left off

### Resuming a session

Because we set `session.reset.mode` to `"never"` in Step 2, your session
is always resumable:

```bash
# This resumes the last session for the "main" agent automatically
apptainer exec apptainer/openclaw.sif \
  openclaw agent --local --agent main \
  -m "Continue where we left off. What were we working on?"
```

The agent loads its prior conversation history and continues naturally.

### Listing sessions

```bash
apptainer exec apptainer/openclaw.sif openclaw sessions
```

### Starting a fresh session

When you want to start clean (not resume):

```bash
# Change the reset mode to "always" for one run, or simply
# create a new named agent for a different project:
apptainer exec apptainer/openclaw.sif \
  openclaw agents add my-new-project

apptainer exec apptainer/openclaw.sif \
  openclaw agent --local --agent my-new-project \
  -m "Starting a brand new analysis..."
```

---

## Quick Reference

### One-shot query

```bash
module load apptainer/1.4.2
apptainer exec apptainer/openclaw.sif \
  openclaw agent --local --agent main -m "Your question here"
```

### Interactive session on a compute node

```bash
srun --pty --mem=1G --time=02:00:00 bash
module load apptainer/1.4.2
apptainer exec apptainer/openclaw.sif \
  openclaw agent --local --agent main -m "Let's work on something"
```

### Batch job

```bash
OPENCLAW_PROMPT="Your task here" sbatch apptainer/slurm-openclaw.sh
```

### Pass API key explicitly (instead of ~/.openclaw/.env)

```bash
apptainer exec --env ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  apptainer/openclaw.sif openclaw agent --local --agent main -m "Hello"
```

---

## Environment Variables

### API Keys

| Variable             | Provider                  |
|---------------------|---------------------------|
| `ANTHROPIC_API_KEY` | Anthropic (Claude)        |
| `OPENAI_API_KEY`    | OpenAI (GPT-4o)           |
| `OPENROUTER_API_KEY`| OpenRouter (multi-model)  |
| `GEMINI_API_KEY`    | Google Gemini             |

### Overrides

| Variable                   | Purpose                    | Default              |
|---------------------------|----------------------------|----------------------|
| `OPENCLAW_STATE_DIR`      | State/config directory     | `~/.openclaw`        |
| `OPENCLAW_CONFIG_PATH`    | Config file path           | `~/.openclaw/openclaw.json` |
| `OPENCLAW_PROMPT`         | Prompt for batch jobs      | (greeting)           |

Pass any of these to the container with `--env`:

```bash
apptainer exec --env ANTHROPIC_API_KEY=sk-ant-... apptainer/openclaw.sif ...
```

---

## Troubleshooting

### "apptainer: command not found"

```bash
module load apptainer/1.4.2
# Or find available versions:
module spider apptainer
```

### Container build fails with "Failed to create thread"

Login nodes restrict process counts. Always build on a compute node:

```bash
srun --mem=4G --time=00:30:00 --cpus-per-task=2 \
  apptainer build apptainer/openclaw.sif apptainer/openclaw.def
```

### Container build fails (disk space)

```bash
df -h ~
# If /tmp is full:
export APPTAINER_TMPDIR=$HOME/tmp && mkdir -p $APPTAINER_TMPDIR
```

### API connection errors

Engaging compute nodes have outbound internet. Verify with:

```bash
srun --pty bash -c "curl -sI https://api.anthropic.com"
```

### API key not found

- Check your env file: `cat ~/.openclaw/.env`
- Or pass explicitly: `--env ANTHROPIC_API_KEY=sk-ant-...`
- Make sure the key matches the model provider

### Node.js or module errors

The container bundles Node.js 22 and all dependencies. If you see module
errors, the image may be corrupt — rebuild it.

---

## The Apptainer Recipe

The container definition (`apptainer/openclaw.def`) is intentionally minimal:

```
Bootstrap: docker
From: ghcr.io/openclaw/openclaw:main
```

It pulls the official Docker image (same one used on DigitalOcean and in
`docker-compose.yml`) and adds a thin wrapper script so the `openclaw` CLI
works from any working directory. No custom build steps, no GPU drivers,
no special dependencies. When the upstream image is updated, just rebuild
the `.sif`:

```bash
srun --mem=4G --time=00:30:00 --cpus-per-task=2 \
  apptainer build --force apptainer/openclaw.sif apptainer/openclaw.def
```

---

## Comparison: DigitalOcean vs Engaging

| Feature              | DigitalOcean Droplet       | MIT Engaging (this guide)  |
|---------------------|---------------------------|---------------------------|
| Container runtime   | Docker                    | Apptainer                 |
| Persistence         | Always-on VM              | Home directory (NFS)      |
| Session survival    | Automatic (systemd)       | Automatic (filesystem)    |
| Compute             | Fixed droplet size        | Flexible SLURM allocation |
| Data access         | Upload to droplet         | Already on cluster        |
| Cost                | Monthly droplet fee       | Free (MIT account)        |
| GPU                 | Extra cost                | Available via `--gres`    |
| Setup time          | ~5 min (1-Click)          | ~10 min (this guide)      |

The key difference: on DigitalOcean the gateway runs as a persistent service.
On Engaging, you run the agent on-demand via SLURM and rely on session
persistence to maintain continuity. The end result is the same — your agent
remembers everything and picks up where it left off.

---

## Next Steps

- **Multiple agents**: Create isolated agents for different projects:
  `openclaw agents add <name>`
- **Tool use**: Extend the agent with shell commands, web search, file I/O,
  and custom skills
- **Memory**: OpenClaw persists knowledge in SQLite with vector search — all
  stored in `~/.openclaw/`, surviving across SLURM jobs
- **Channels**: Connect to Telegram, Discord, Slack, etc. for messaging
  (requires a long-running gateway job or port forwarding)
- **Share with your lab**: Copy the `.sif` file to a shared directory — each
  user's state is isolated in their own `~/.openclaw/`

For full documentation, see [docs.openclaw.ai](https://docs.openclaw.ai) and
the [OpenClaw repository](https://github.com/openclaw/openclaw).
