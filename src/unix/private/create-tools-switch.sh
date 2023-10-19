#!/bin/sh
# -------------------------------------------------------
# create-tools-switch.sh
#
# Purpose:
# 1. Make or upgrade an Opam switch tied to the current installation of Diskuv OCaml and the
#    current DKMLABI.
# 2. Not touch any existing installations of Diskuv OCaml (if blue-green deployments are enabled)
#
# When invoked?
# On Windows as part of `setup-userprofile.ps1`
# which is itself invoked by `install-world.ps1`.
#
# -------------------------------------------------------
set -euf

# ------------------
# BEGIN Command line processing

usage() {
    printf "%s\n" "Usage:" >&2
    printf "%s\n" "    create-tools-switch.sh -h                      Display this help message" >&2
    printf "%s\n" "    create-tools-switch.sh -p DKMLABI              Create the [dkml] switch" >&2
    printf "%s\n" "Opam root directory:" >&2
    printf "%s\n" "    If -d STATEDIR then <STATEDIR>/opam is the Opam root directory." >&2
    printf "%s\n" "    Otherwise the Opam root directory is the user's standard Opam root directory." >&2
    printf "%s\n" "Opam [dkml] switch:" >&2
    printf "%s\n" "    The default [dkml] switch is the 'dkml' global switch." >&2
    printf "%s\n" "    In highest precedence order:" >&2
    printf "%s\n" "    1. If the environment variable DKSDK_INVOCATION is set to ON," >&2
    printf "%s\n" "       the [dkml] switch will be the 'dksdk-<DKML_HOST_ABI>' global switch." >&2
    printf "%s\n" "    2. If there is a Diskuv OCaml installation, then the [dkml] switch will be" >&2
    printf "%s\n" "       the local <DiskuvOCamlHome>/dkml switch." >&2
    printf "%s\n" "    These rules allow for the DKML OCaml system compiler to be distinct from" >&2
    printf "%s\n" "    any DKSDK OCaml system compiler." >&2
    printf "%s\n" "Options:" >&2
    printf "%s\n" "    -p DKMLABI: The DKML ABI for the tools" >&2
    printf "%s\n" "    -d STATEDIR: If specified, use <STATEDIR>/opam as the Opam root" >&2
    printf "%s\n" "    -u ON|OFF: Deprecated" >&2
    printf "%s\n" "    -w: Disable updating of opam repositories. Useful when already updated (ex. by init-opam-root.sh)" >&2
    printf "%s\n" "    -f FLAVOR: Optional. The flavor of DkML \"global-compile\" distribution packages to install:" >&2
    printf "%s\n" "          Dune, CI or Full" >&2
    printf "%s\n" "       'Full' is the same as 'CI', but has packages for UIs like utop and a language server" >&2
    printf "%s\n" "       If not specified, no global-compile packages are installed unless [-a EXTRAPKG] is used" >&2
    printf "%s\n" "    -b BUILDTYPE: The build type which is one of:" >&2
    printf "%s\n" "        Debug" >&2
    printf "%s\n" "        Release - Most optimal code. Should be faster than ReleaseCompat* builds" >&2
    printf "%s\n" "        ReleaseCompatPerf - Compatibility with 'perf' monitoring tool." >&2
    printf "%s\n" "        ReleaseCompatFuzz - Compatibility with 'afl' fuzzing tool." >&2
    printf "%s\n" "       Ignored when -v OCAMLVERSION_OR_HOME is a OCaml home" >&2
    printf "%s\n" "    -v OCAMLVERSION_OR_HOME: Optional. The OCaml version or OCaml home (containing usr/bin/ocaml or bin/ocaml)" >&2
    printf "%s\n" "       to use. The OCaml home determines the native code produced by the switch." >&2
    printf "%s\n" "       Examples: 4.13.1, /usr, /opt/homebrew" >&2
    printf "%s\n" "    -o OPAMEXE_OR_HOME: Optional. If a directory, it is the home for Opam containing bin/opam-real or bin/opam." >&2
    printf "%s\n" "       If an executable, it is the opam to use (and when there is an opam shim the opam-real can be used)" >&2
    printf "%s\n" "    -a EXTRAPKG: Optional; can be repeated. An extra package to install in the tools switch" >&2
}

EXTRAPKGS=
BUILDTYPE=
STATEDIR=
OCAMLVERSION_OR_HOME=
OPAMEXE_OR_HOME=
FLAVOR=
DKMLABI=
DISABLE_UPDATE=OFF
while getopts ":hb:d:u:o:p:v:f:a:w" opt; do
    case ${opt} in
        h )
            usage
            exit 0
        ;;
        b )
            BUILDTYPE=$OPTARG
        ;;
        d )
            STATEDIR=$OPTARG
        ;;
        u ) true ;;
        v )
            OCAMLVERSION_OR_HOME=$OPTARG
        ;;
        o ) OPAMEXE_OR_HOME=$OPTARG ;;
        p )
            DKMLABI=$OPTARG
            if [ "$DKMLABI" = dev ]; then
                usage
                exit 0
            fi
            ;;
        f )
            case "$OPTARG" in
                Dune|DUNE|dune) FLAVOR=Dune ;;
                Ci|CI|ci)       FLAVOR=CI ;;
                Full|FULL|full) FLAVOR=Full ;;
                *)
                    printf "%s\n" "FLAVOR must be Dune, CI or Full"
                    usage
                    exit 1
            esac
        ;;
        a )
            if [ -n "$EXTRAPKGS" ]; then
                EXTRAPKGS="$EXTRAPKGS $OPTARG"
            else
                EXTRAPKGS="$OPTARG"
            fi
        ;;
        w ) DISABLE_UPDATE=ON ;;
        \? )
            printf "%s\n" "This is not an option: -$OPTARG" >&2
            usage
            exit 1
        ;;
    esac
done
shift $((OPTIND -1))

# END Command line processing
# ------------------

if [ -z "$DKMLABI" ]; then
    printf "Must specify -p DKMLABI option\n" >&2
    usage
    exit 1
fi

# Set deprecated, implicit USERMODE
if [ -n "$STATEDIR" ]; then
    USERMODE=OFF
else
    # shellcheck disable=SC2034
    USERMODE=ON
fi

DKMLDIR=$(dirname "$0")
DKMLDIR=$(cd "$DKMLDIR/../../../../.." && pwd)

# shellcheck disable=SC1091
. "$DKMLDIR"/vendor/drc/unix/_common_tool.sh

# From here onwards everything should be run using RELATIVE PATHS ...
# >>>>>>>>>

# -----------------------
# BEGIN create system switch

# Set NUMCPUS if unset from autodetection of CPUs
autodetect_cpus

# Set DKML_POSIX_SHELL
autodetect_posix_shell

# Get OCaml version
case "$OCAMLVERSION_OR_HOME" in
    /* | ?:*) # /a/b/c or C:\Windows
        get_ocamlver() {
            validate_and_explore_ocamlhome "$OCAMLVERSION_OR_HOME"
            # the `awk ...` is dos2unix equivalent
            OCAMLVERSION=$("$DKML_OCAMLHOME_ABSBINDIR_UNIX/ocamlc" -version | awk '{ sub(/\r$/,""); print }')
        }
        ;;
    *)
        if [ -z "$BUILDTYPE" ]; then
            usage
            printf "FATAL: Missing -b BUILDTYPE. Required except when -v OCAMLHOME is specified and contains usr/bin/ocaml or bin/ocaml\n" >&2
            exit 1
        fi
        get_ocamlver() {
            OCAMLVERSION="$OCAMLVERSION_OR_HOME"
        }
        ;;
esac

# Just the OCaml compiler
if [ "$DISABLE_UPDATE" = ON ]; then
    do_cos1() {
        log_trace "$DKMLDIR"/vendor/drd/src/unix/create-opam-switch.sh -y -s -v "$OCAMLVERSION_OR_HOME" -o "$OPAMEXE_OR_HOME" -b "$BUILDTYPE" -p "$DKMLABI" -w
    }
else
    do_cos1() {
        log_trace "$DKMLDIR"/vendor/drd/src/unix/create-opam-switch.sh -y -s -v "$OCAMLVERSION_OR_HOME" -o "$OPAMEXE_OR_HOME" -b "$BUILDTYPE" -p "$DKMLABI"
    }
fi
if [ -n "$STATEDIR" ]; then
    do_cos2() {
        do_cos1 -d "$STATEDIR"
    }
else
    do_cos2() {
        do_cos1
    }
fi
do_cos2

# END create system switch
# -----------------------

# --------------------------------
# BEGIN Opam troubleshooting script

# Set OPAMSWITCHFINALDIR_BUILDHOST, OPAMSWITCHNAME_EXPAND of `dkml` switch
# and set OPAMROOTDIR_BUILDHOST, OPAMROOTDIR_EXPAND
set_opamswitchdir_of_system "$DKMLABI"

cat > "$WORK"/troubleshoot-opam.sh <<EOF
#!/bin/sh
set -euf
OPAMROOT='$OPAMROOTDIR_BUILDHOST'
printf "\n\n========= [START OF TROUBLESHOOTING] ===========\n\n" >&2
if find . -maxdepth 0 -mmin -240 2>/dev/null >/dev/null; then
    FINDARGS="-mmin -240" # is -mmin supported? BSD (incl. macOS), MSYS2, GNU
else
    FINDARGS="-mtime -1" # use 1 day instead. Solaris
fi
find "\$OPAMROOT"/log -mindepth 1 -maxdepth 1 \$FINDARGS \( -name "*.out" -o -name "*.env" \) ! -name "log-*.out" ! -name "ocaml-variants-*.out" | while read -r dump_on_error_LOG; do
    dump_on_error_BLOG=\$(basename "\$dump_on_error_LOG")
    printf "\n\n========= [TROUBLESHOOTING] %s ===========\n\n" "\$dump_on_error_BLOG" >&2
    awk -v BLOG="\$dump_on_error_BLOG" '{print "[" BLOG "]", \$0}' "\$dump_on_error_LOG" >&2
done
printf "\nScroll up to see the [TROUBLESHOOTING] logs that begin at the [START OF TROUBLESHOOTING] line\n" >&2
EOF
chmod +x "$WORK"/troubleshoot-opam.sh

# END Opam troubleshooting script
# --------------------------------

# --------------------------------
# BEGIN Flavor packages

{
    printf "%s" "exec '$DKMLDIR'/vendor/drd/src/unix/private/platform-opam-exec.sh -s -v '$OCAMLVERSION_OR_HOME' -o '$OPAMEXE_OR_HOME' \"\$@\" install -y"
    printf " %s" "--jobs=$NUMCPUS"
    if [ -n "$EXTRAPKGS" ]; then
        printf " %s" "$EXTRAPKGS"
    fi
    globalcompile_awk="$DKMLDIR/vendor/drd/src/unix/private/global-compile.awk"
    case "$FLAVOR" in
        "")
            ;;
        Dune)
            get_ocamlver
            awk -f "$globalcompile_awk" "$DKMLDIR"/vendor/drd/src/none/dune-anyver-pkgs.txt | tr -d '\r'
            awk -f "$globalcompile_awk" "$DKMLDIR"/vendor/drd/src/none/dune-"$OCAMLVERSION"-pkgs.txt | tr -d '\r'
            ;;
        CI)
            get_ocamlver
            awk -f "$globalcompile_awk" "$DKMLDIR"/vendor/drd/src/none/dune-anyver-pkgs.txt | tr -d '\r'
            awk -f "$globalcompile_awk" "$DKMLDIR"/vendor/drd/src/none/dune-"$OCAMLVERSION"-pkgs.txt | tr -d '\r'
            awk -f "$globalcompile_awk" "$DKMLDIR"/vendor/drd/src/none/ci-anyver-pkgs.txt | tr -d '\r'
            awk -f "$globalcompile_awk" "$DKMLDIR"/vendor/drd/src/none/ci-"$OCAMLVERSION"-pkgs.txt | tr -d '\r'
            ;;
        Full)
            get_ocamlver
            awk -f "$globalcompile_awk" "$DKMLDIR"/vendor/drd/src/none/dune-anyver-pkgs.txt | tr -d '\r'
            awk -f "$globalcompile_awk" "$DKMLDIR"/vendor/drd/src/none/dune-"$OCAMLVERSION"-pkgs.txt | tr -d '\r'
            awk -f "$globalcompile_awk" "$DKMLDIR"/vendor/drd/src/none/ci-anyver-pkgs.txt | tr -d '\r'
            awk -f "$globalcompile_awk" "$DKMLDIR"/vendor/drd/src/none/ci-"$OCAMLVERSION"-pkgs.txt | tr -d '\r'
            awk -f "$globalcompile_awk" "$DKMLDIR"/vendor/drd/src/none/full-anyver-pkgs.txt | tr -d '\r'
            awk -f "$globalcompile_awk" "$DKMLDIR"/vendor/drd/src/none/full-"$OCAMLVERSION"-pkgs.txt | tr -d '\r'
            ;;
        *) printf "%s\n" "FATAL: Unsupported flavor $FLAVOR" >&2; exit 107
    esac
} > "$WORK"/config-dkml.sh
if [ -n "$STATEDIR" ]; then
    if ! log_shell "$WORK"/config-dkml.sh -p "$DKMLABI" -d "$STATEDIR"; then
        "$WORK"/troubleshoot-opam.sh
        exit 107
    fi
else
    if ! log_shell "$WORK"/config-dkml.sh -p "$DKMLABI"; then
        "$WORK"/troubleshoot-opam.sh
        exit 107
    fi
fi

# END Flavor packages
# --------------------------------
