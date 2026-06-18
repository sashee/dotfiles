# Case: nested sandboxing. A shell (zsh, __NIX_UTILS_SKIP_SANDBOX=false) re-sandboxes
# each tool it launches, so `zsh -> node` gives node its OWN sandbox. A non-shell
# tool (node here, like claude: skip defaults to true) runs nested tools INSIDE its
# own sandbox, so `claude -> node` reuses claude's sandbox instead of wrapping again.
#
# Discriminator: node-nonet (network=false). If it gets its own sandbox, seccomp
# blocks socket(AF_INET) and a bind fails; if it reuses a network=true parent's
# sandbox, the bind succeeds. (machine-id can't tell the two apart — a nested
# sandbox inherits the parent's faked id.)
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
in
{
  testScript = ''
    # Policy: shells set skip=false (re-sandbox children); other tools default to
    # true (children reuse the sandbox) — claude is the latter.
    assert run_user("zsh -c 'printenv __NIX_UTILS_SKIP_SANDBOX'").strip() == "false", "zsh should set skip=false"
    assert run_user("node ${probes.printSkip}").strip() == "true", "non-shell tools default to skip=true"

    # zsh -> node-nonet: re-sandboxed, so node-nonet's no-network restriction applies
    # and the inet bind fails.
    run_user("zsh -c 'node-nonet ${probes.bindUdp}'", succeed=False)

    # node -> node-nonet: node-nonet sees skip=true, bypasses bwrap, and binds inside
    # the outer node's network=true sandbox -> succeeds (proves the sandbox is reused,
    # not re-applied).
    run_user("node ${probes.reuseProbe} node-nonet ${probes.bindUdp}")
  '';
}
