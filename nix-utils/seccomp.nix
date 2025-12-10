{
	pkgs,
	options ? {},
}:
let
	# Address family mappings
	afMap = {
		AF_INET = 2;
		AF_INET6 = 10;
		AF_UNIX = 1;
		AF_NETLINK = 16;
		AF_PACKET = 17;
		AF_BLUETOOTH = 31;
	};

	# Get block options
	blockOpts = options.block or {};

	# Collect blocked AF numbers
	blocked_af = builtins.map (name: afMap.${name}) (
		builtins.filter (name: blockOpts.${name} or false) (builtins.attrNames afMap)
	);

	cSource = ''
#include <seccomp.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>

#define EACCES   13

int main() {
    scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_ALLOW);
    if (!ctx) {
        fprintf(stderr, "seccomp_init failed\n");
        return 1;
    }

${builtins.concatStringsSep "\n" (map (af: ''
    // Block socket(${toString af}, ...) - return EACCES
    if (seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EACCES), SCMP_SYS(socket), 1,
                          SCMP_A0(SCMP_CMP_EQ, ${toString af})) < 0) {
        fprintf(stderr, "Failed to add socket rule for AF ${toString af}\n");
        return 1;
    }
'') blocked_af)}

    if (seccomp_export_bpf(ctx, STDOUT_FILENO) < 0) {
        fprintf(stderr, "seccomp_export_bpf failed\n");
        return 1;
    }

    seccomp_release(ctx);
    return 0;
}
'';

	sourceFile = pkgs.writeText "seccomp-filter-gen.c" cSource;
in
pkgs.stdenv.mkDerivation {
	name = "seccomp-filter";

	src = sourceFile;

	buildInputs = [ pkgs.libseccomp ];

	unpackPhase = "true";

	buildPhase = ''
		$CC -o gen-filter ${sourceFile} -lseccomp
		./gen-filter > filter.bpf
	'';

	installPhase = ''
		mkdir -p $out
		cp filter.bpf $out/
	'';
}
