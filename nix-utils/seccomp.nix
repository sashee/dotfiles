{
	pkgs,
	options ? {},
}:
let
	# Build the C source based on options
	block_inet = options.block_inet or false;

	cSource = ''
#include <seccomp.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>

#define AF_INET  2
#define AF_INET6 10
#define EACCES   13

int main() {
    scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_ALLOW);
    if (!ctx) {
        fprintf(stderr, "seccomp_init failed\n");
        return 1;
    }

${if block_inet then ''
    // Block socket(AF_INET, ...) - return EACCES
    if (seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EACCES), SCMP_SYS(socket), 1,
                         SCMP_A0(SCMP_CMP_EQ, AF_INET)) < 0) {
        fprintf(stderr, "Failed to add AF_INET socket rule\n");
        return 1;
    }

    // Block socket(AF_INET6, ...) - return EACCES
    if (seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EACCES), SCMP_SYS(socket), 1,
                         SCMP_A0(SCMP_CMP_EQ, AF_INET6)) < 0) {
        fprintf(stderr, "Failed to add AF_INET6 socket rule\n");
        return 1;
    }
'' else ""}

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
