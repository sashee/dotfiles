# Case: broad launch/smoke coverage — every tool's sandbox can be set up, real
# binaries start in their sandbox, and zsh-intended tools start via zsh (nested
# re-sandbox). Enumerates whatever tools are installed on the machine, so on the
# dotfiles tester (full scripts-env) and the image repo's common-desktop it covers
# all of them. All checks redirect stdin from /dev/null and use a timeout so a tool
# that waits for input can't hang the suite.
{ pkgs }:
let
  # Real-binary launch checks (only tools with a clean headless version/flag). Tools
  # without one are covered by their -debug sandbox check instead: the TUIs (isd,
  # bluetuith), the no-version CLIs (k2pdfopt, fx, qrread), and the GUI apps that
  # init a toolkit and abort headlessly (keepassxc SIGABRTs on --version; vlc and
  # libreoffice likewise can't be relied on without a display). chromium/flameshot
  # do print --version headlessly, so they stay.
  versionMap = {
    git = "--version"; node = "--version"; npm = "--version"; npx = "--version";
    aws = "--version"; duckdb = "--version"; sqlite3 = "--version"; jwt = "--version";
    wormhole = "--version"; lazygit = "--version"; nvim = "--version";
    zsh = "--version"; tmux = "-V"; zellij = "--version";
    opencode = "--version"; claude = "--version";
    chromium = "--version"; flameshot = "--version";
  };
  # Programs intended to be launched from zsh (the zsh_programs list in lib.nix).
  zshPrograms = [
    "aws" "awslogs" "duckdb" "sqlite3" "flameshot" "fx" "git" "isd" "k2pdfopt"
    "lazygit" "lazysql" "wormhole" "opencode" "claude" "vlc" "nvim" "node" "jwt"
    "libreoffice"
  ];
in
{
  testScript = ''
    def present(x):
        return run_user(f"command -v {x} >/dev/null 2>&1 && echo y || echo n").strip() == "y"

    # 1) Every tool's sandbox sets up: <tool>-debug runs `bash -c true` inside the
    #    tool's real sandbox (no binary/display/network needed).
    # Discover <tool>-debug wrappers across the login-shell PATH (not the hardcoded
    # /run/current-system/sw/bin: the aarch64 machine installs tools in another
    # profile). run_user is a login shell, so $PATH covers whatever profile they're in.
    debugs = run_user(
        "IFS=:; for d in $PATH; do ls \"$d\" 2>/dev/null; done | grep -- '-debug$' | sort -u"
    ).split()
    assert len(debugs) >= 10, f"expected many -debug tools, got {debugs}"
    for d in debugs:
        run_user(f"timeout 60 {d} -c true </dev/null >/dev/null 2>&1")

    # 2) Real binaries launch in their sandbox (curated --version map; skip absent).
    for tool, flag in ${builtins.toJSON versionMap}.items():
        if present(tool):
            run_user(f"timeout 60 {tool} {flag} </dev/null >/dev/null 2>&1")

    # 3) zsh-intended programs start via zsh (zsh sets skip=false -> nested sandbox).
    for z in ${builtins.toJSON zshPrograms}:
        if present(z + "-debug"):
            run_user(f"timeout 60 zsh -c '{z}-debug -c true' </dev/null >/dev/null 2>&1")
  '';
}
