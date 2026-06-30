# ssh-rpi — ssh to the rpi with the host-tools-mcp broker socket forwarded,
# solving the "nested dir doesn't exist after a reboot" problem dynamically.
#
# The broker socket has to end up at the NESTED path
# ${TMPDIR:-/tmp}/host-tools-mcp/broker.sock on the Pi, because a sandboxed
# mcp-register (zellij) only sees that bind-mounted dir. But `ssh -R` binds the
# forward BEFORE the remote command runs, and that dir is gone after a reboot
# (/tmp is tmpfs). So instead we:
#   - forward to a UNIQUE FLAT path under /tmp — /tmp always exists (no pre-created
#     dir needed) and the unique name never collides with a stale leftover socket;
#   - then the remote command (which runs AFTER the bind) makes the dir and MOVES
#     the forwarded socket into the nested path (a rename keeps the bound socket live
#     at its new path, and it now lives inside the bound dir so the sandbox sees it).
# `mv -f` deletes any stale broker.sock before writing, so setup is idempotent and
# self-healing — no exit-cleanup trap needed (a trap wouldn't fire on SIGKILL/power
# loss anyway; the next connection just overwrites the leftover).
# One ssh connection (one agent ack), no ControlMaster, no server-side config.
# (mv is a same-filesystem rename; the flat path and the broker dir are both under
# /tmp in the default setup, so this holds.)
#
# Extra args are passed straight to ssh, before the host, e.g.:
#   ssh-rpi -L 8080:8080
#   ssh-rpi -v
set -euo pipefail

# Where our broker listens on THIS machine — the -R forward's local target.
local_broker="${TMPDIR:-/tmp}/host-tools-mcp/broker.sock"

# Unique flat remote bind path (always bindable, collision-free across reconnects).
fwd="/tmp/.htm-fwd-$$-${RANDOM}${RANDOM}.sock"

# Runs on the Pi AFTER the forward is bound: move the forwarded socket to the nested
# broker path (overwriting any stale leftover), then a normal interactive login shell.
remote_cmd=$(cat <<REMOTE
dir="\${TMPDIR:-/tmp}/host-tools-mcp"
mkdir -p "\$dir"
mv -f "$fwd" "\$dir/broker.sock"
"\${SHELL:-/bin/bash}" -l
REMOTE
)

exec ssh \
	-o ExitOnForwardFailure=yes \
	-o "RemoteForward=$fwd $local_broker" \
	-t \
	"$@" \
	rpi \
	"$remote_cmd"
