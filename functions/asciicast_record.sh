stty size | read -r orig_rows orig_cols && stty cols 80 rows 24 && F=$(mktemp -u) && mkdir -p $F && asciinema rec "$F/rec.json" && stty cols $orig_cols rows $orig_rows && docker run --rm -v $F:/data asciinema/asciicast2gif "rec.json" $1 && mv "$F/$1" $PWD && rm -r $F
