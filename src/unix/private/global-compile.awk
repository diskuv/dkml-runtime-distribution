/^ *## *global-compile$/ {
    emit_next_package=1;
}
NF>0 && $1 !~ "#.*" && emit_next_package==1 {
    printf " %s", $1;
    emit_next_package=0
}
