{
	pkgs,
}:
let
	findGitRootSource = pkgs.writeText "findGitRoot.rs" ''
use std::env;
use std::process;

fn main() {
    let cwd = match env::current_dir() {
        Ok(dir) => dir,
        Err(err) => {
            eprintln!("failed to get current directory: {err}");
            process::exit(1);
        }
    };

    let mut current = cwd.as_path();
    loop {
        if current.join(".git").exists() {
            println!("{}", current.display());
            return;
        }

        match current.parent() {
            Some(parent) => current = parent,
            None => {
                println!("{}", cwd.display());
                return;
            }
        }
    }
}
	'';

	findGitRoot = pkgs.stdenv.mkDerivation {
		name = "findGitRoot";
		dontUnpack = true;
		nativeBuildInputs = [pkgs.rustc];

		buildPhase = ''
			${pkgs.rustc}/bin/rustc ${findGitRootSource} -O -o findGitRoot
		'';

		installPhase = ''
			mkdir -p $out/bin
			cp findGitRoot $out/bin/findGitRoot
		'';
	};
in
	{
		inherit findGitRoot;
	}
