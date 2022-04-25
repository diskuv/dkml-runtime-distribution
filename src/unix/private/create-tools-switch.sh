#!/bin/sh
# -------------------------------------------------------
# create-tools-switch.sh
#
# Purpose:
# 1. Make or upgrade an Opam switch tied to the current installation of Diskuv OCaml and the
#    current DKMLPLATFORM.
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
    printf "%s\n" "    create-tools-switch.sh -h           Display this help message" >&2
    printf "%s\n" "    create-tools-switch.sh              Create the Diskuv system switch" >&2
    printf "%s\n" "                                                    at <DiskuvOCamlHome>/dkml on Windows or" >&2
    printf "%s\n" "                                                    <OPAMROOT>/dkml/_opam on non-Windows" >&2
    printf "%s\n" "    create-tools-switch.sh -d STATEDIR -p DKMLPLATFORM  Create the Diskuv system switch" >&2
    printf "%s\n" "                                                        at <STATEDIR>/dkml" >&2
    printf "%s\n" "Options:" >&2
    printf "%s\n" "    -p DKMLPLATFORM: The DKML platform for the tools" >&2
    printf "%s\n" "    -d STATEDIR: If specified and -u ON enabled, use <STATEDIR>/opam as the Opam root" >&2
    printf "%s\n" "    -u ON|OFF: User mode. If OFF, sets Opam --root to <STATEDIR>/opam." >&2
    printf "%s\n" "       If ON, uses Opam 2.2+ default root" >&2
    printf "%s\n" "    -f FLAVOR: Optional; defaults to CI. The flavor of system packages: 'CI' or 'Full'" >&2
    printf "%s\n" "       'Full' is the same as CI, but has packages for UIs like utop and a language server" >&2
    printf "%s\n" "    -v OCAMLVERSION_OR_HOME: Optional. The OCaml version or OCaml home (containing usr/bin/ocaml or bin/ocaml)" >&2
    printf "%s\n" "       to use. The OCaml home determines the native code produced by the switch." >&2
    printf "%s\n" "       Examples: 4.13.1, /usr, /opt/homebrew" >&2
    printf "%s\n" "    -o OPAMHOME: Optional. Home directory for Opam containing bin/opam or bin/opam.exe" >&2
    printf "%s\n" "    -a EXTRAPKG: Optional; can be repeated. An extra package to install in the tools switch" >&2
}

STATEDIR=
USERMODE=ON
OCAMLVERSION_OR_HOME=
OPAMHOME=
FLAVOR=CI
DKMLPLATFORM=
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
        u )
            USERMODE=$OPTARG
        ;;
        v )
            OCAMLVERSION_OR_HOME=$OPTARG
        ;;
        o ) OPAMHOME=$OPTARG ;;
        p )
            DKMLPLATFORM=$OPTARG
            if [ "$DKMLPLATFORM" = dev ]; then
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

if [ -z "$DKMLPLATFORM" ]; then
    printf "Must specify -p DKMLPLATFORM option\n" >&2
    usage
    exit 1
fi

DKMLDIR=$(dirname "$0")
DKMLDIR=$(cd "$DKMLDIR/../../../../.." && pwd)

# shellcheck disable=SC1091
. "$DKMLDIR"/vendor/dkml-runtime-common/unix/_common_tool.sh

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
            OCAMLVERSION=$("$DKML_OCAMLHOME_UNIX/$DKML_OCAMLHOME_BINDIR_UNIX/ocamlc" -version | awk '{ sub(/\r$/,""); print }')
            ;;
        *)
            OCAMLVERSION="$OCAMLVERSION_OR_HOME"
            ;;
    esac
}

# Just the OCaml compiler
log_trace "$DKMLDIR"/vendor/dkml-runtime-distribution/src/unix/create-opam-switch.sh -y -s -v "$OCAMLVERSION_OR_HOME" -o "$OPAMHOME" -b Release -d "$STATEDIR" -u "$USERMODE" -p "$DKMLPLATFORM"

# Flavor packages
{
    printf "%s" "exec '$DKMLDIR'/vendor/dkml-runtime-distribution/src/unix/private/platform-opam-exec.sh -s -v '$OCAMLVERSION_OR_HOME' -o '$OPAMHOME' \"\$@\" install -y"
    printf " %s" "--jobs=$NUMCPUS"
    if [ -n "$EXTRAPKGS" ]; then
        printf " %s" "$EXTRAPKGS"
    fi
    case "$FLAVOR" in
        CI)
            awk 'NF>0 && $1 !~ "#.*" {printf " %s", $1}' "$DKMLDIR"/vendor/dkml-runtime-distribution/src/none/ci-pkgs.txt | tr -d '\r'
            ;;
        Full)
            get_ocamlver
            awk 'NF>0 && $1 !~ "#.*" {printf " %s", $1}' "$DKMLDIR"/vendor/dkml-runtime-distribution/src/none/ci-pkgs.txt | tr -d '\r'
            awk 'NF>0 && $1 !~ "#.*" {printf " %s", $1}' "$DKMLDIR"/vendor/dkml-runtime-distribution/src/none/full-anyver-no-ci-pkgs.txt | tr -d '\r'
            awk 'NF>0 && $1 !~ "#.*" {printf " %s", $1}' "$DKMLDIR"/vendor/dkml-runtime-distribution/src/none/full-"$OCAMLVERSION"-no-ci-pkgs.txt | tr -d '\r'
            ;;
        *) printf "%s\n" "FATAL: Unsupported flavor $FLAVOR" >&2; exit 107
    esac
} > "$WORK"/config-dkml.sh
log_shell "$WORK"/config-dkml.sh -d "$STATEDIR" -u "$USERMODE" -p "$DKMLPLATFORM"

# END create system switch
# -----------------------
