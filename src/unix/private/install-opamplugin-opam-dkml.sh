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
    printf "%s\n" "    -p PLATFORM: (Deprecated) The target platform or 'dev'" >&2
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
if [ "${DKML_FEATUREFLAG_CMAKE_PLATFORM:-OFF}" = OFF ]; then
    USERMODE=OFF
else
    USERMODE=ON
fi
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
            if [ ! "${DKML_FEATUREFLAG_CMAKE_PLATFORM:-OFF}" = OFF ] && [ "$PLATFORM" = dev ]; then
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
. "$DKMLDIR"/vendor/dkml-runtime-common/unix/_common_tool.sh

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

OPAMFILE_BUILDHOST="$DKMLDIR"/vendor/dkml-runtime-distribution/opam-files/opam-dkml.opam
if [ -x /usr/bin/cygpath ]; then
    OPAMFILE_BUILDHOST=$(/usr/bin/cygpath -aw "$OPAMFILE_BUILDHOST")
fi
if [ "${DKML_FEATUREFLAG_CMAKE_PLATFORM:-OFF}" = OFF ]; then
    "$DKMLDIR"/vendor/dkml-runtime-distribution/src/unix/private/platform-opam-exec.sh -s \
    install "$OPAMFILE_BUILDHOST" --yes
else
    "$DKMLDIR"/vendor/dkml-runtime-distribution/src/unix/private/platform-opam-exec.sh -s -p "$PLATFORM" -d "$STATEDIR" -u "$USERMODE" -o "$OPAMHOME" -v "$OCAMLVERSION_OR_HOME" \
    install "$OPAMFILE_BUILDHOST" --yes --verbose --debug-level 2
fi

# END opam install opam-dkml
# -----------------------

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# END           ON-DEMAND OPAM ROOT INSTALLATIONS
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
