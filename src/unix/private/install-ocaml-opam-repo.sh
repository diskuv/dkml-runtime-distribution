#!/bin/sh
# ----------------------------
# install-ocaml-opam-repo.sh DKMLDIR DOCKER_IMAGE OCAML_HOME INSTALLDIR

set -euf

DKMLDIR=$1
shift
if [ ! -e "$DKMLDIR/.dkmlroot" ]; then echo "Expected a DKMLDIR at $DKMLDIR but no .dkmlroot found" >&2; fi

DOCKER_IMAGE=$1
shift

OCAMLHOME=$1
shift

INSTALLDIR=$1
shift

# shellcheck disable=SC2034
PLATFORM=dev # not actually in the dev platform but we are just pulling the "common" tool functions (so we can choose whatever platform we like)

# Because Cygwin has a max 260 character limit of absolute file names, we place the working directories in /tmp. We do not need it
# relative to TOPDIR since we are not using sandboxes.
TMPPARENTDIR_BUILDHOST=$(mktemp -d /tmp/dkmlp.XXXXX)

# shellcheck disable=SC1091
. "$DKMLDIR"/vendor/dkml-runtime-common/unix/_common_tool.sh

# Keep the _common_tool provided temporary directory, even when we switch into the reproducible directory
# so the reproducible directory does not leak anything
export TMPPARENTDIR_BUILDHOST

# Change the EXIT trap to clean our shorter tmp dir
trap 'rm -rf "$TMPPARENTDIR_BUILDHOST"' EXIT

# To be portable whether we build scripts in the container or not, we
# change the directory to always be in the DKMLDIR (just like the container
# sets the directory to be /work)
cd "$DKMLDIR"

# From here onwards everything should be run using RELATIVE PATHS ...
# >>>>>>>>>

if [ -e "$INSTALLDIR"/"$SHARE_OCAML_OPAM_REPO_RELPATH"/repo ] && [ -e "$INSTALLDIR"/"$SHARE_OCAML_OPAM_REPO_RELPATH"/pins.txt ]; then
    echo 'SUCCESS. Already installed'
    exit 0
fi

# Get DKML_OCAMLHOME_UNIX, DKML_OCAMLHOME_BINDIR_UNIX and OCAMLVERSION
validate_and_explore_ocamlhome "$OCAMLHOME"
OCAMLEXE="$DKML_OCAMLHOME_UNIX/$DKML_OCAMLHOME_BINDIR_UNIX/ocamlc"
OCAML_VERSION=$("$OCAMLEXE" -config | awk '$1=="version:"{print $2}' | tr -d '\r')
if [ -z "$OCAML_VERSION" ]; then
    printf "FATAL: %s -config failed to give the OCaml version\n" "$OCAMLEXE" >&2
    exit 107
fi

# Install the source code
log_trace "$DKMLDIR"/vendor/dkml-runtime-distribution/src/unix/private/r-f-oorepo-1-setup.sh \
    -d "$DKMLDIR" \
    -t "$INSTALLDIR" \
    -v "$DOCKER_IMAGE" \
    -a "amd64" \
    -b "$OCAML_VERSION" \
    -c "$OCAMLHOME"

# Use reproducible directory created by setup
cd "$INSTALLDIR"

# Fetch and install
log_trace "$SHARE_REPRODUCIBLE_BUILD_RELPATH"/200-fetch-oorepo-"$OCAML_VERSION"/vendor/dkml-runtime-distribution/src/unix/private/r-f-oorepo-2-build-noargs.sh
# Trim
log_trace "$SHARE_REPRODUCIBLE_BUILD_RELPATH"/200-fetch-oorepo-"$OCAML_VERSION"/vendor/dkml-runtime-distribution/src/unix/private/r-f-oorepo-9-trim-noargs.sh
