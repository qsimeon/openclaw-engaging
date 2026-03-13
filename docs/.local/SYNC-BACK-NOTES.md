# Sync-Back Notes for orcd-docs-edit PR #169

*Updated 2026-03-12 from openclaw-engaging cluster session*

These are the changes to sync back to `docs/recipes/openclaw-engaging.md` in
the orcd-docs-edit repo. Implementation is done and pushed.

**PR**: #169 at `mit-orcd/orcd-docs-edit`, branch `qs/openclaw-engaging`
**Status**: Lauren requested changes (6 comments), all replied to, needs re-review.
Lauren's latest comment: use `~/orcd/scratch` as the scratch path.
**Reference**: `docs/engaging-apptainer-guide.md` in openclaw-engaging has the
full updated text you can crib from.

**Latest fixes (2026-03-12)**:
- Fixed critical container build bug: upstream Docker image creates a symlink
  `/usr/local/bin/openclaw` → `/app/openclaw.mjs`. Our `cat >` followed the
  symlink and overwrote the real JS entrypoint. Fix: `rm -f` the symlink first.
- Container verified working: `openclaw --version` → `2026.3.11`
- All fork files pass deepscan audit (consistent paths, API keys, bind mounts)
- Fixed hardcoded PI storage path in orcd-workspace-init.sh → now auto-detects
- Fixed setup.sh: HPC config was applied before onboarding (wizard overwrote it).
  Now applied AFTER onboarding using `openclaw config set` commands.
- Fixed onboard-only memory: `--mem=1G` OOM killed → changed to `--mem=4G`

**Walkthrough findings (2026-03-12)** — full fresh-user walkthrough completed:
- Build: works, ~10 min on compute node. Himalaya v1.0.0 download 404 (non-fatal)
- Onboarding: works with 4G memory. Wizard is interactive and clear.
- Gateway: works after config fix. Token not auto-filling in dashboard URL (upstream UI).
- Agent identity: workspace seeding (TOOLS.md, SOUL.md) works — agent knows about
  Engaging, SLURM, ORCD storage, partitions, etc.
- Agent limitation: sbatch not accessible from inside Apptainer container (SLURM
  binaries not bind-mounted). Agent worked around it by running Python directly.
- Agent limitation: cannot display images inline in gateway chat (sends path instead).
- Gateway restart needed after moving ~/.openclaw to symlink (ENOTDIR error)

**Future feature ideas:**
- RAG-based TOOLS.md: populate workspace from live orcd-docs via orcd-rag instead
  of static content (keeps agent knowledge current as docs change)
- Custom `--home` for Apptainer container (Lauren's use case: point container home
  to scratch instead of real home). Needs CONFIG_FILE path update in slurm-gateway.sh.
- start-multi.sh for parallel gateway instances (already implemented)

---

## Changes to make (in priority order)

### 1. Storage — use `~/orcd/scratch` as the default path

Lauren confirmed: the standard scratch path for users is `~/orcd/scratch`
(which symlinks to `/orcd/scratch/orcd/002/$USER`). Every ORCD user has this.

**The recipe should recommend moving `.openclaw` to scratch:**

```markdown
!!! tip "Move `.openclaw` to scratch storage"
    Home directories have quotas (~195 GB). Move `.openclaw` to scratch early:

    ```bash
    mkdir -p ~/orcd/scratch/openclaw
    cp -a ~/.openclaw/. ~/orcd/scratch/openclaw/
    rm -rf ~/.openclaw
    ln -s ~/orcd/scratch/openclaw ~/.openclaw
    ```

    Or use PI/group storage if available (persistent, not auto-purged):
    ```bash
    ln -s /orcd/data/<pi-group>/$USER/openclaw ~/.openclaw
    ```

!!! warning
    Scratch may be purged after ~90 days of inactivity. If using scratch,
    periodically back up `~/.openclaw/openclaw.json` and `credentials/`.
```

Also update the "How It Works" section where it says state is stored in
`~/.openclaw/` on your home directory — add that users should move it to
`~/orcd/scratch` to avoid quota issues.

### 2. Gateway launch — use `start-gateway.sh`

Replace Step 4 (`sbatch` + manual `cat`) with:

```markdown
### Step 4: Launch the Web Dashboard

```bash
cd ~/openclaw-engaging
./apptainer/start-gateway.sh
```

The launcher submits the SLURM job, waits for it to start, and prints the
SSH tunnel command + dashboard URL automatically.

> **Manual alternative:** `sbatch apptainer/slurm-gateway.sh` then
> `cat openclaw-gw-<jobid>.out`
```

### 3. Responsible use & data privacy (Lauren's #1 ask)

Add a prominent warning near the top, right after the intro:

```markdown
!!! warning "Responsible Use and Data Privacy"
    - **Only use low-risk data.** Prompts and file excerpts are sent to
      cloud LLM APIs for processing. Do not use restricted or
      export-controlled data. See
      [MIT data classification](https://ist.mit.edu/security/data-classification).
    - **Limit access.** Only bind-mount directories the agent needs.
    - **Review third-party skills** before enabling — they execute code
      with your permissions.
    - **Monitor API usage.** Some providers have suspended accounts for
      very high automated usage. Be mindful of costs with batch jobs.
```

### 4. Sandboxing — clarify `--containall` position

Our scripts use default Apptainer (auto-mount home) for usability.
Chris Hill recommended `--containall`. Present both:

```markdown
!!! note "Sandboxing approach"
    The scripts disable OpenClaw's internal sandbox (it requires Docker,
    unavailable on HPC) and rely on Apptainer as the security boundary.
    The container filesystem is read-only — the agent can't modify the
    host OS or affect other users.

    By default, Apptainer auto-mounts your home directory. For stricter
    isolation, use `--containall` with explicit `-B` bind mounts — but
    note this limits the agent's ability to explore the filesystem and
    discover datasets.
```

### 5. API usage ban warning (Lauren's #5)

Add under "Changing the Model" or "Tips":

```markdown
!!! warning "API Usage Limits"
    Autonomous agents can generate significant API traffic. Some providers
    have suspended accounts for exceeding automated usage thresholds.
    Monitor usage and costs, especially with batch jobs.
```

### 6. New features (optional — "Tips" or "Advanced" section)

Briefly mention these implemented features:

- **`./apptainer/start-gateway.sh`** — 1-click launcher (covered in #2)
- **`./apptainer/start-multi.sh N`** — N parallel gateway instances on
  consecutive ports (18790, 18791, ...) for class demos
- **`./apptainer/orcd-workspace-init.sh`** — auto-populates agent workspace
  with cluster knowledge; agents know about SLURM, storage, modules
- **Symlink bind-mount** — all scripts auto-detect `~/.openclaw` symlinks
  and bind the target into the container automatically

---

## What NOT to change

- **Port 18790** — correct, matches implementation
- **SSH tunnel approach** — correct, Lauren approved
- **`openclaw` alias** — correct, setup.sh installs it
- **Login node `orcd-login.mit.edu`** — correct default

---

## Commit message suggestion

```
Address PR review feedback + sync with implementation

- Storage: use ~/orcd/scratch as default path (Lauren's suggestion)
- Replace sbatch+cat with start-gateway.sh for dashboard launch
- Add responsible use & data privacy warning (top of doc)
- Clarify sandboxing: Apptainer default vs --containall
- Add API usage limits warning
- Mention start-multi.sh, workspace init in tips section
```
