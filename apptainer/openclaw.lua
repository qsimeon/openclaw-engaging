-- openclaw.lua — Lmod modulefile for OpenClaw on MIT Engaging HPC
--
-- setup.sh installs this file to ~/modulefiles/openclaw.lua automatically.
-- To activate:
--   1. Add to ~/.bashrc:  module use ~/modulefiles
--   2. Per session:       module load openclaw
--
-- Or set OPENCLAW_REPO if you cloned somewhere else:
--   OPENCLAW_REPO=~/my/path/openclaw-engaging module load openclaw

help([[
OpenClaw AI assistant on MIT Engaging HPC.
Provides the 'openclaw' command via Apptainer container.
Guide: docs/engaging-apptainer-guide.md
]])

whatis("OpenClaw AI assistant via Apptainer")

depends_on("apptainer/1.4.2")

-- Locate the repo (default: ~/orcd/scratch/oclaw/openclaw-engaging)
local repo = os.getenv("OPENCLAW_REPO")
              or pathJoin(os.getenv("HOME"), "orcd/scratch/oclaw/openclaw-engaging")
local wrapper = pathJoin(repo, "apptainer", "openclaw-engaging.sh")

-- Containall on by default (set OPENCLAW_CONTAINALL=0 to disable)
setenv("OPENCLAW_CONTAINALL", "1")

-- Provide the 'openclaw' command as a shell function
set_shell_function("openclaw", wrapper .. ' "$@"', wrapper .. ' "$@"')
