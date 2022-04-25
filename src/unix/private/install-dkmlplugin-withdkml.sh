#!/bin/sh
# -------------------------------------------------------
# install-dkmlplugin-withdkml.sh PLATFORM
#
# Purpose:
# 1. Compile with-dkml into the plugins/diskuvocaml/ of the OPAMROOT.
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
    printf "%s\n" "    install-dkmlplugin-withdkml.sh -h                   Display this help message" >&2
    printf "%s\n" "    install-dkmlplugin-withdkml.sh -p PLATFORM          (Deprecated) Install the DKML plugin with-dkml" >&2
    printf "%s\n" "    install-dkmlplugin-withdkml.sh [-d STATEDIR] -p DKMLPLATFORM  Install the DKML plugin with-dkml" >&2
    printf "%s\n" "      Without '-d' the Opam root will be the Opam 2.2 default" >&2
    printf "%s\n" "Options:" >&2
    printf "%s\n" "    -p DKMLPLATFORM: The DKML platform (not 'dev')" >&2
    printf "%s\n" "    -d STATEDIR: If specified and -u ON enabled, use <STATEDIR>/opam as the Opam root" >&2
    printf "%s\n" "    -u ON|OFF: User mode. If OFF, sets Opam --root to <STATEDIR>/opam." >&2
    printf "%s\n" "       If ON, uses Opam 2.2+ default root" >&2
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
while getopts ":hp:d:u:o:v:" opt; do
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
            STATEDIR=$OPTARG
        ;;
        u )
            USERMODE=$OPTARG
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

# -----------------------
# BEGIN install with-dkml (with-dkml)

if [ ! -x "$WITHDKMLEXE_BUILDHOST" ]; then
    # Create a temp directory containing dkml-apps.opam and the dkml-apps source code.
    #
    #  dkml-apps.opam
    #  vendor/ (need all of it since many files are crunched into apps/common/dune:scripts.ml)
    #     drd/
    #       src/msys2/apps/with-dkml/with_dkml.ml
    #  .dkmlroot (needed for apps/common/dune)
    WITHDKML_SRC_UNIX="$WORK"/src
    install -d "$WITHDKML_SRC_UNIX"
    install "$DKMLDIR"/.dkmlroot "$WITHDKML_SRC_UNIX/"
    install "$DKMLDIR"/vendor/drd/opam-files/dkml-apps.opam "$WITHDKML_SRC_UNIX/"
    cp -rp "$DKMLDIR"/vendor "$WITHDKML_SRC_UNIX/"

    # Since dkml-apps code is interspersed with opam-dkml, get rid of opam-dkml
    rm -rf "$WITHDKML_SRC_UNIX/vendor/drd/src/msys2/apps/opam-dkml"

    # Compile with Dune into temp build directory
    WITHDKML_BUILD_UNIX="$WORK"/build
    if [ -x /usr/bin/cygpath ]; then
        WITHDKML_SRC_BUILDHOST=$(/usr/bin/cygpath -aw "$WITHDKML_SRC_UNIX")
        WITHDKML_BUILD_BUILDHOST=$(/usr/bin/cygpath -aw "$WITHDKML_BUILD_UNIX")
    else
        WITHDKML_SRC_BUILDHOST="$WITHDKML_SRC_UNIX"
        WITHDKML_BUILD_BUILDHOST="$WITHDKML_BUILD_UNIX"
    fi
    install -d "$WITHDKML_SRC_UNIX"
    "$DKMLDIR"/vendor/drd/src/unix/private/platform-opam-exec.sh -s -p "$PLATFORM" -d "$STATEDIR" -u "$USERMODE" -o "$OPAMHOME" -v "$OCAMLVERSION_OR_HOME" \
        -- exec -- dune build --root "$WITHDKML_SRC_BUILDHOST" --build-dir "$WITHDKML_BUILD_BUILDHOST" vendor/drd/src/msys2/apps/with-dkml/with_dkml.exe

    # Place in plugins
    install -d "$WITHDKMLEXEDIR_BUILDHOST"
    install "$WITHDKML_BUILD_BUILDHOST/default/vendor/drd/src/msys2/apps/with-dkml/with_dkml.exe" "$WITHDKMLEXE_BUILDHOST"
fi

# END install with-dkml (with-dkml)
# -----------------------

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# END           ON-DEMAND OPAM ROOT INSTALLATIONS
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
