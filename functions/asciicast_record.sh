F=$(mktemp -u) && mkdir -p $F && asciinema rec "$F/rec.json" && docker run --rm -v $F:/data asciinema/asciicast2gif "rec.json" $1 && mv "$F/$1" $PWD && rm -r $F
