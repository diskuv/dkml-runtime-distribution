#!/bin/sh
# -------------------------------------------------------
# install-opamplugin-opam-dkml.sh PLATFORM
#
# Purpose:
# 1. Opam install `opam-dkml` plugin.
#
# When invoked?
# On Windows as part of `setup-userprofile.ps1`
# which is itself invoked by `install-world.ps1`. On both
# Windows and Unix it is also invoked as part of `build-sandbox-init-common.sh`.
#
# Prerequisites:
# - init-opam-root.sh
# - create-tools-switch.sh
#
# -------------------------------------------------------
set -euf

# ------------------
# BEGIN Command line processing

usage() {
    printf "%s\n" "Usage:" >&2
    printf "%s\n" "    install-opamplugin-opam-dkml.sh -h                   Display this help message" >&2
    printf "%s\n" "    install-opamplugin-opam-dkml.sh -p PLATFORM          (Deprecated) Install the Opam plugin opam-dkml" >&2
    printf "%s\n" "    install-opamplugin-opam-dkml.sh [-d STATEDIR] -p DKMLPLATFORM       Install the Opam plugin opam-dkml" >&2
    printf "%s\n" "      Without '-d' the Opam root will be the Opam 2.2 default" >&2
    printf "%s\n" "Options:" >&2
    printf "%s\n" "    -p DKMLPLATFORM: The DKML platform (not 'dev')" >&2
    printf "%s\n" "    -d STATEDIR: If specified, use <STATEDIR>/opam as the Opam root" >&2
    printf "%s\n" "    -o OPAMHOME: Optional. Home directory for Opam containing bin/opam or bin/opam.exe." >&2
    printf "%s\n" "       The bin/ subdir of the Opam home is added to the PATH" >&2
    printf "%s\n" "    -v OCAMLVERSION_OR_HOME: Optional. The OCaml version or OCaml home (containing bin/ocaml) to use." >&2
    printf "%s\n" "       Examples: 4.13.1, /usr, /opt/homebrew" >&2
    printf "%s\n" "       The bin/ subdir of the OCaml home is added to the PATH; currently, passing an OCaml version does nothing" >&2
}

PLATFORM=
STATEDIR=
USERMODE=ON
OPAMHOME=
OCAMLVERSION_OR_HOME=
while getopts ":hp:d:o:v:" opt; do
    case ${opt} in
        h )
            usage
            exit 0
        ;;
        p )
            PLATFORM=$OPTARG
            if [ "$PLATFORM" = dev ]; then
                usage
                exit 0
            fi
        ;;
        d )
            # shellcheck disable=SC2034
            STATEDIR=$OPTARG
            # shellcheck disable=SC2034
            USERMODE=OFF
        ;;
        o ) OPAMHOME=$OPTARG ;;
        v ) OCAMLVERSION_OR_HOME=$OPTARG ;;
        \? )
            printf "%s\n" "This is not an option: -$OPTARG" >&2
            usage
            exit 1
        ;;
    esac
done
shift $((OPTIND -1))

if [ -z "$PLATFORM" ]; then
    usage
    exit 1
fi

# END Command line processing
# ------------------

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

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# BEGIN         ON-DEMAND OPAM ROOT INSTALLATIONS
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# We use the Opam plugin directory to hold our root-specific installations.
# http://opam.ocaml.org/doc/Manual.html#opam-root
#
# In Diskuv OCaml each architecture gets its own Opam root.

# Set OPAMROOTDIR_BUILDHOST and OPAMROOTDIR_EXPAND and WITHDKMLEXE(DIR)_BUILDHOST
set_opamrootdir

# Set DKML_POSIX_SHELL
autodetect_posix_shell

# -----------------------
# BEGIN opam install opam-dkml

# Create a temp directory containing opam-dkml.opam and the opam-dkml source
# code. opam-dkml requires dkml_apps_common which comes from dkml-apps.opam.
#
#  opam-dkml.opam
#  dkml-apps.opam
#  vendor/ (need all of it since many files are crunched into apps/common/dune:scripts.ml)
#     drd/
#       src/msys2/apps/opam-dkml/opam_dkml.ml
#       src/msys2/apps/with-dkml/with_dkml.ml
#  .dkmlroot (needed for apps/common/dune)
OPAMDKML_SRC_UNIX="$WORK"/src
install -d "$OPAMDKML_SRC_UNIX"
install "$DKMLDIR"/.dkmlroot "$OPAMDKML_SRC_UNIX/"
install "$DKMLDIR"/vendor/drd/opam-files/opam-dkml.opam "$OPAMDKML_SRC_UNIX/"
install "$DKMLDIR"/vendor/drd/opam-files/dkml-apps.opam "$OPAMDKML_SRC_UNIX/"
cp -rp "$DKMLDIR"/vendor "$OPAMDKML_SRC_UNIX/"

# opam install
OPAMFILE_BUILDHOST="$OPAMDKML_SRC_UNIX"/opam-dkml.opam
if [ -x /usr/bin/cygpath ]; then
    OPAMFILE_BUILDHOST=$(/usr/bin/cygpath -aw "$OPAMFILE_BUILDHOST")
fi
"$DKMLDIR"/vendor/drd/src/unix/private/platform-opam-exec.sh -s -p "$PLATFORM" -d "$STATEDIR" -u "$USERMODE" -o "$OPAMHOME" -v "$OCAMLVERSION_OR_HOME" \
    install "$OPAMFILE_BUILDHOST" --yes

# END opam install opam-dkml
# -----------------------

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# END           ON-DEMAND OPAM ROOT INSTALLATIONS
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
