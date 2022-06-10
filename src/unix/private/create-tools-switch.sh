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
    printf "%s\n" "    -f FLAVOR: Optional; defaults to CI. The flavor of system packages: 'CI' or 'Full'" >&2
    printf "%s\n" "       'Full' is the same as CI, but has packages for UIs like utop and a language server" >&2
    printf "%s\n" "    -v OCAMLVERSION_OR_HOME: Optional. The OCaml version or OCaml home (containing usr/bin/ocaml or bin/ocaml)" >&2
    printf "%s\n" "       to use. The OCaml home determines the native code produced by the switch." >&2
    printf "%s\n" "       Examples: 4.13.1, /usr, /opt/homebrew" >&2
    printf "%s\n" "    -o OPAMHOME: Optional. Home directory for Opam containing bin/opam or bin/opam.exe" >&2
    printf "%s\n" "    -a EXTRAPKG: Optional; can be repeated. An extra package to install in the tools switch" >&2
}

STATEDIR=
OCAMLVERSION_OR_HOME=
OPAMHOME=
FLAVOR=CI
DKMLABI=
EXTRAPKGS=
while getopts ":hd:u:o:p:v:f:a:" opt; do
    case ${opt} in
        h )
            usage
            exit 0
        ;;
        d )
            STATEDIR=$OPTARG
        ;;
        u ) true ;;
        v )
            OCAMLVERSION_OR_HOME=$OPTARG
        ;;
        o ) OPAMHOME=$OPTARG ;;
        p )
            DKMLABI=$OPTARG
            if [ "$DKMLABI" = dev ]; then
                usage
                exit 0
            fi
            ;;
        f )
            case "$OPTARG" in
                Ci|CI|ci)       FLAVOR=CI ;;
                Full|FULL|full) FLAVOR=Full ;;
                *)
                    printf "%s\n" "FLAVOR must be CI or Full"
                    usage
                    exit 1
            esac
        ;;
        a )
            if [ -n "$EXTRAPKGS" ]; then
                EXTRAPKGS="$EXTRAPKGS "
            fi
            EXTRAPKGS="$EXTRAPKGS $OPTARG"
        ;;
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

# To be portable whether we build scripts in the container or not, we
# change the directory to always be in the TOPDIR (just like the container
# sets the directory to be /work mounted to TOPDIR)
cd "$TOPDIR"

# From here onwards everything should be run using RELATIVE PATHS ...
# >>>>>>>>>

# -----------------------
# BEGIN create system switch

# Set NUMCPUS if unset from autodetection of CPUs
autodetect_cpus

# Set DKML_POSIX_SHELL
autodetect_posix_shell

# Get OCaml version
get_ocamlver() {
    case "$OCAMLVERSION_OR_HOME" in
        /* | ?:*) # /a/b/c or C:\Windows
            validate_and_explore_ocamlhome "$OCAMLVERSION_OR_HOME"
            # the `awk ...` is dos2unix equivalent
            OCAMLVERSION=$("$DKML_OCAMLHOME_ABSBINDIR_UNIX/ocamlc" -version | awk '{ sub(/\r$/,""); print }')
            ;;
        *)
            OCAMLVERSION="$OCAMLVERSION_OR_HOME"
            ;;
    esac
}

# Just the OCaml compiler
if [ -n "$STATEDIR" ]; then
    log_trace "$DKMLDIR"/vendor/drd/src/unix/create-opam-switch.sh -y -s -v "$OCAMLVERSION_OR_HOME" -o "$OPAMHOME" -b Release -p "$DKMLABI" -d "$STATEDIR"
else
    log_trace "$DKMLDIR"/vendor/drd/src/unix/create-opam-switch.sh -y -s -v "$OCAMLVERSION_OR_HOME" -o "$OPAMHOME" -b Release -p "$DKMLABI"
fi

# Flavor packages
{
    printf "%s" "exec '$DKMLDIR'/vendor/drd/src/unix/private/platform-opam-exec.sh -s -v '$OCAMLVERSION_OR_HOME' -o '$OPAMHOME' \"\$@\" install -y"
    printf " %s" "--jobs=$NUMCPUS"
    if [ -n "$EXTRAPKGS" ]; then
        printf " %s" "$EXTRAPKGS"
    fi
    case "$FLAVOR" in
        CI)
            awk 'NF>0 && $1 !~ "#.*" {printf " %s", $1}' "$DKMLDIR"/vendor/drd/src/none/ci-pkgs.txt | tr -d '\r'
            ;;
        Full)
            get_ocamlver
            awk 'NF>0 && $1 !~ "#.*" {printf " %s", $1}' "$DKMLDIR"/vendor/drd/src/none/ci-pkgs.txt | tr -d '\r'
            awk 'NF>0 && $1 !~ "#.*" {printf " %s", $1}' "$DKMLDIR"/vendor/drd/src/none/full-anyver-no-ci-pkgs.txt | tr -d '\r'
            awk 'NF>0 && $1 !~ "#.*" {printf " %s", $1}' "$DKMLDIR"/vendor/drd/src/none/full-"$OCAMLVERSION"-no-ci-pkgs.txt | tr -d '\r'
            ;;
        *) printf "%s\n" "FATAL: Unsupported flavor $FLAVOR" >&2; exit 107
    esac
} > "$WORK"/config-dkml.sh
if [ -n "$STATEDIR" ]; then
    log_shell "$WORK"/config-dkml.sh -p "$DKMLABI" -d "$STATEDIR"
else
    log_shell "$WORK"/config-dkml.sh -p "$DKMLABI"
fi

# END create system switch
# -----------------------
