#!/bin/bash
# -------------------------------------------------------
# platform-opam-exec.sh [-b BUILDTYPE] [-s | -p PLATFORM] [--] install|clean|help|...
#
# PLATFORM=dev|linux_arm32v6|linux_arm32v7|windows_x86|...
#
#   The PLATFORM can be `dev` which means the dev platform using the native CPU architecture
#   and system binaries for Opam from your development machine.
#   Otherwise it is one of the "PLATFORMS" canonically defined in TOPDIR/Makefile.
#
# BUILDTYPE=Debug|Release|...
#
#   One of the "BUILDTYPES" canonically defined in TOPDIR/Makefile.
#
# The build is placed in build/$PLATFORM.
# -------------------------------------------------------
set -euf

DKMLDIR=$(dirname "$0")
DKMLDIR=$(cd "$DKMLDIR"/../../../../.. && pwd)

# shellcheck disable=SC1091
. "$DKMLDIR/vendor/dkml-runtime-common/unix/crossplatform-functions.sh"

# ------------------
# BEGIN Command line processing

usage() {
    printf "%s\n" "Usage:" >&2
    printf "%s\n" "    platform-opam-exec.sh -h                                                    Display this help message" >&2
    printf "%s\n" "    platform-opam-exec.sh -p PLATFORM [--] init|help|switch remove|...          (Deprecated) Run the opam command" >&2
    printf "%s\n" "                                                                             in the PLATFORM's active switch" >&2
    printf "%s\n" "    platform-opam-exec.sh -p PLATFORM -b BUILDTYPE [--] install|clean|help|...  (Deprecated) Run the opam command" >&2
    printf "%s\n" "                                                                             in the PLATFORM's BUILDTYPE switch" >&2
    printf "%s\n" "    platform-opam-exec.sh -p PLATFORM                                           (Deprecated) Run the opam command" >&2
    printf "%s\n" "                            -t OPAMSWITCH [--] install|clean|help|..." >&2
    printf "%s\n" "    platform-opam-exec.sh -s [--] install|clean|help|...                        (Deprecated) Run the opam command" >&2
    printf "%s\n" "                                                                             in the 'diskuv-host-tools' local switch" >&2
    printf "%s\n" "    platform-opam-exec.sh -u ON -t OPAMSWITCH [--] install|clean|help|...      Run the opam command in the specified" >&2
    printf "%s\n" "                                                                               switch" >&2
    printf "%s\n" "    platform-opam-exec.sh -s -u ON [--] install|clean|help|...                 Run the opam command in the global" >&2
    printf "%s\n" "                                                                               'diskuv-host-tools' switch" >&2
    printf "%s\n" "    platform-opam-exec.sh -d STATEDIR [-u OFF] [--] install|clean|help|...     Run the opam command in the local" >&2
    printf "%s\n" "                                                                               switch prefix of STATEDIR/_opam" >&2
    printf "%s\n" "    platform-opam-exec.sh -d STATEDIR -s [-u OFF] [--] install|clean|help|...  Run the opam command in the local" >&2
    printf "%s\n" "                                                                               switch prefix of STATEDIR/host-tools/_opam" >&2
    printf "%s\n" "Options:" >&2
    printf "%s\n" "    -p PLATFORM: (Deprecated) The target platform or 'dev'" >&2
    printf "%s\n" "    -p DKMLPLATFORM: The DKML platform (not 'dev'); must be present if -s option since part of the switch name" >&2
    printf "%s\n" "    -s: Select the 'diskuv-host-tools' switch. If specified adds --switch to opam" >&2
    printf "%s\n" "    -b BUILDTYPE: Optional. The build type. If specified adds --switch to opam" >&2
    printf "%s\n" "    -t OPAMSWITCH: The target Opam switch. If specified adds --switch to opam" >&2
    printf "%s\n" "    -d STATEDIR: Use <STATEDIR>/_opam as the Opam switch prefix, unless [-s] is also" >&2
    printf "%s\n" "       selected which uses <STATEDIR>/host-tools/_opam, and unless [-s] [-u ON] is also" >&2
    printf "%s\n" "       selected which uses <DiskuvOCamlHome>/host-tools/_opam on Windows and" >&2
    printf "%s\n" "       <OPAMROOT>/diskuv-host-tools/_opam on non-Windows." >&2
    printf "%s\n" "       Opam init shell scripts search the ancestor paths for an '_opam' directory, so" >&2
    printf "%s\n" "       the non-system switch will be found if you are in <STATEDIR>" >&2
    printf "%s\n" "    -u ON|OFF: User mode. If OFF, sets Opam --root to <STATEDIR>/opam." >&2
    printf "%s\n" "       Defaults to ON; ie. using Opam 2.2+ default root." >&2
    printf "%s\n" "       Also affects the Opam switches; see [-d STATEDIR] option" >&2
    printf "%s\n" "    -o OPAMHOME: Optional. Home directory for Opam containing bin/opam or bin/opam.exe." >&2
    printf "%s\n" "       The bin/ subdir of the Opam home is added to the PATH" >&2
    printf "%s\n" "    -v OCAMLVERSION_OR_HOME: Optional. The OCaml version or OCaml home (containing bin/ocaml) to use." >&2
    printf "%s\n" "       Examples: 4.13.1, /usr, /opt/homebrew" >&2
    printf "%s\n" "       The bin/ subdir of the OCaml home is added to the PATH; currently, passing an OCaml version does nothing" >&2
    printf "%s\n" "Advanced Options:" >&2
    printf "%s\n" "    -0 PREHOOK: If specified, the script will be 'eval'-d upon" >&2
    printf "%s\n" "          entering the Build Sandbox _before_ any the opam command is run." >&2
    printf "%s\n" "    -1 PREHOOK: If specified, the Bash statements will be 'eval'-d twice upon" >&2
    printf "%s\n" "          entering the Build Sandbox _before_ any the opam command is run." >&2
    printf "%s\n" "          It behaves similar to:" >&2
    printf "%s\n" '            eval "the PREHOOK you gave" > /tmp/eval.sh' >&2
    printf "%s\n" '            eval /tmp/eval.sh' >&2
    printf "%s\n" '          Useful for setting environment variables (possibly from a script).' >&2
}

# no arguments should display usage
if [ "$#" -eq 0 ]; then
    usage
    exit 1
fi

# Problem 1:
#
#   Opam (and Dune) do not like:
#     opam --root abc --switch xyz exec ocaml
#   Instead it expects:
#     opam exec --root abc --switch xyz ocaml
#   We want to inject `--root abc` and `--switch xyz` right after the subcommand but before
#   any arg seperators like `--`.
#   For example, we can't just add `--switch xyz` to the end of the command line
#   because we wouldn't be able to support:
#     opam exec something.exe -- --some-arg-for-something abc
#   where the `--switch xyz` **must** go before `--`.
#
# Solution 1:
#
#   Any arguments that can go in 'opam --somearg somecommand' should be processed here
#   and added to OPAM_OPTS. We'll parse 'somecommand ...' options in a second getopts loop.
PLATFORM=
BUILDTYPE=
DISKUV_TOOLS_SWITCH=OFF
STATEDIR=
PREHOOK_SINGLE_EVAL=
PREHOOK_DOUBLE_EVAL=
TARGET_OPAMSWITCH=
ADD_SWITCH_OPTS=OFF
if [ "${DKML_FEATUREFLAG_CMAKE_PLATFORM:-OFF}" = OFF ]; then
    USERMODE=OFF
else
    USERMODE=ON
fi
OPAMHOME=
OCAMLVERSION_OR_HOME=
while getopts ":h0:1:b:sp:t:d:u:o:v:" opt; do
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
        b )
            BUILDTYPE=$OPTARG
            ADD_SWITCH_OPTS=ON
        ;;
        s )
            DISKUV_TOOLS_SWITCH=ON
            ADD_SWITCH_OPTS=ON
        ;;
        d )
            STATEDIR=$OPTARG
        ;;
        u )
            # shellcheck disable=SC2034
            USERMODE=$OPTARG
        ;;
        t )
            TARGET_OPAMSWITCH=$OPTARG
            ADD_SWITCH_OPTS=ON
        ;;
        o ) OPAMHOME=$OPTARG ;;
        v ) OCAMLVERSION_OR_HOME=$OPTARG ;;
        0 )
            PREHOOK_SINGLE_EVAL=$OPTARG
        ;;
        1 )
            PREHOOK_DOUBLE_EVAL=$OPTARG
        ;;
        \? )
            printf "%s\n" "This is not an option: -$OPTARG" >&2
            usage
            exit 1
        ;;
    esac
done
shift $((OPTIND -1))

if [ "${DKML_FEATUREFLAG_CMAKE_PLATFORM:-OFF}" = OFF ]; then
    if [ -z "$PLATFORM" ] && [ "$DISKUV_TOOLS_SWITCH" = OFF ]; then
        usage
        exit 1
    fi
else
    if [ -z "$STATEDIR" ] && cmake_flag_off "$USERMODE"; then
        usage
        exit 1
    fi
    if [ "$DISKUV_TOOLS_SWITCH" = ON ] && [ -z "${PLATFORM:-}" ]; then
        printf "Missing -p DKMLPLATFORM option when -s chosen\n" >&2
        usage
        exit 1
    fi
    if [ "$DISKUV_TOOLS_SWITCH" = OFF ] && [ -z "$TARGET_OPAMSWITCH" ] && ! cmake_flag_off "$USERMODE"; then
        usage
        exit 1
    fi
fi

if [ "${1:-}" = "--" ]; then # supports `platform-opam-exec.sh ... -- --version`
    shift
fi

# END Command line processing
# ------------------

# Win32 conversions
if [ -x /usr/bin/cygpath ]; then
    if [ -n "$OPAMHOME" ]; then OPAMHOME=$(/usr/bin/cygpath -am "$OPAMHOME"); fi
fi

# `diskuv-host-tools` is the host architecture, so use `dev` as its platform
if [ "$DISKUV_TOOLS_SWITCH" = ON ]; then
    if [ "${DKML_FEATUREFLAG_CMAKE_PLATFORM:-OFF}" = OFF ]; then
        PLATFORM=dev
    fi
fi

if [ "${DKML_FEATUREFLAG_CMAKE_PLATFORM:-OFF}" = OFF ]; then
    if [ -n "${BUILDTYPE:-}" ] || [ -n "${DKML_DUNE_BUILD_DIR:-}" ]; then
        # shellcheck disable=SC1091
        . "$DKMLDIR"/vendor/dkml-runtime-common/unix/_common_build.sh
    else
        # shellcheck disable=SC1091
        . "$DKMLDIR"/vendor/dkml-runtime-common/unix/_common_tool.sh
    fi
else
    if [ -n "${STATEDIR:-}" ]; then
        # shellcheck disable=SC1091
        . "$DKMLDIR"/vendor/dkml-runtime-common/unix/_common_build.sh
    else
        # shellcheck disable=SC1091
        . "$DKMLDIR"/vendor/dkml-runtime-common/unix/_common_tool.sh
    fi
fi

# To be portable whether we build scripts in the container or not, we
# change the directory to always be in the TOPDIR (just like the container
# sets the directory to be /work mounted to TOPDIR)
cd "$TOPDIR"

# From here onwards everything should be run using RELATIVE PATHS ...
# >>>>>>>>>

# no subcommand should display help
if [ $# -eq 0 ]; then
    usage
    exit 1
else
    subcommand=$1; shift
fi

OPAM_OPTS=()
# shellcheck disable=SC2034
PLATFORM_EXEC_PRE_SINGLE="$PREHOOK_SINGLE_EVAL"
PLATFORM_EXEC_PRE_DOUBLE="$PREHOOK_DOUBLE_EVAL"
OPAM_ENV_STMT=

# ------------
# BEGIN --root

# Set OPAMEXE
set_opamexe

# Set OPAMROOTDIR_BUILDHOST and OPAMROOTDIR_EXPAND
set_opamrootdir

# We check if the root exists before we add --root
OPAM_ROOT_OPT=() # we have a separate array for --root since --root is mandatory for `opam init`
if is_minimal_opam_root_present "$OPAMROOTDIR_BUILDHOST"; then
    OPAM_ROOT_OPT+=( --root "$OPAMROOTDIR_EXPAND" )
    # `--set-switch` will output the globally selected switch, if any.
    OPAM_ENV_STMT="'$OPAMEXE'"' env --quiet --root "'$OPAMROOTDIR_EXPAND'" --set-root --set-switch || true'
fi

# END --root
# ------------

# ------------
# BEGIN --switch

# Set $DKMLHOME_UNIX, $DKMLPARENTHOME_BUILDHOST and other vars
autodetect_dkmlvars || true

# Q: What if there was no switch but there was a root?
# Ans: This section would be skipped, and the earlier `opam env --root yyy --set-root` would have captured the environment with its OPAM_ENV_STMT.

# Set OPAMSWITCHFINALDIR_BUILDHOST and OPAMSWITCHNAME_EXPAND if there is a switch specified
if [ "$DISKUV_TOOLS_SWITCH" = ON ]; then
    # Set OPAMSWITCHFINALDIR_BUILDHOST and OPAMSWITCHNAME_EXPAND of `diskuv-host-tools` switch
    set_opamswitchdir_of_system "$PLATFORM"
elif [ "${DKML_FEATUREFLAG_CMAKE_PLATFORM:-OFF}" = OFF ] && [ -n "${DKML_DUNE_BUILD_DIR:-}" ]; then
    # set --switch only if BUILDTYPE (translated into DKML_DUNE_BUILD_DIR) has been set
    install -d "$DKML_DUNE_BUILD_DIR"

    # Set OPAMROOTDIR_BUILDHOST, OPAMROOTDIR_EXPAND, OPAMSWITCHFINALDIR_BUILDHOST, OPAMSWITCHNAME_EXPAND
    set_opamrootandswitchdir
elif [ -n "${STATEDIR:-}" ]; then
    # Set OPAMROOTDIR_BUILDHOST, OPAMROOTDIR_EXPAND, OPAMSWITCHFINALDIR_BUILDHOST, OPAMSWITCHNAME_EXPAND
    set_opamrootandswitchdir
elif [ -n "$TARGET_OPAMSWITCH" ]; then
    # Set OPAMSWITCHFINALDIR_BUILDHOST, OPAMSWITCHNAME_EXPAND
    if [ -x /usr/bin/cygpath ]; then
        TARGET_OPAMSWITCH_BUILDHOST=$(/usr/bin/cygpath -aw "$TARGET_OPAMSWITCH")
    else
        TARGET_OPAMSWITCH_BUILDHOST="$TARGET_OPAMSWITCH"
    fi
    OPAMSWITCHFINALDIR_BUILDHOST="$TARGET_OPAMSWITCH_BUILDHOST/_opam"
    OPAMSWITCHNAME_EXPAND="$TARGET_OPAMSWITCH_BUILDHOST" # this won't work in containers, but target is meant for 'dev' platform (perhaps we should check_state?)
fi

# We check if the switch exists before we add --switch. Otherwise `opam` will complain:
#   [ERROR] The selected switch C:/source/xxx/build/dev/Debug is not installed.
if [ "${DKML_FEATUREFLAG_CMAKE_PLATFORM:-OFF}" = OFF ]; then
    if [ "$ADD_SWITCH_OPTS" = ON ] &&
    [ -n "${OPAMSWITCHFINALDIR_BUILDHOST:-}" ] && [ -n "${OPAMSWITCHNAME_EXPAND:-}" ] &&
    is_minimal_opam_switch_present "$OPAMSWITCHFINALDIR_BUILDHOST"; then
        OPAM_OPTS+=( --switch "$OPAMSWITCHNAME_EXPAND" )
        OPAM_ENV_STMT="'$OPAMEXE'"' env --quiet --root "'$OPAMROOTDIR_EXPAND'" --switch "'$OPAMSWITCHNAME_EXPAND'" --set-root --set-switch || true'
    fi
else
    if [ -n "${OPAMSWITCHFINALDIR_BUILDHOST:-}" ] && [ -n "${OPAMSWITCHNAME_EXPAND:-}" ] &&
    is_minimal_opam_switch_present "$OPAMSWITCHFINALDIR_BUILDHOST"; then
        OPAM_OPTS+=( --switch "$OPAMSWITCHNAME_EXPAND" )
        OPAM_ENV_STMT="'$OPAMEXE'"' env --quiet --root "'$OPAMROOTDIR_EXPAND'" --switch "'$OPAMSWITCHNAME_EXPAND'" --set-root --set-switch || true'
    fi
fi

# END --switch
# ------------

# We'll make a prehook so that `opam env --root yyy [--switch zzz] --set-root [--set-switch]` is automatically executed.
# We compose prehooks by letting user-specified prehooks override our own. So user-specified prehooks go last so they can override the environment.
if [ -n "${PLATFORM_EXEC_PRE_DOUBLE:-}" ]; then PLATFORM_EXEC_PRE_DOUBLE="; $PLATFORM_EXEC_PRE_DOUBLE"; fi
# shellcheck disable=SC2034 disable=SC2016
PLATFORM_EXEC_PRE_DOUBLE="${OPAM_ENV_STMT:-} ${PLATFORM_EXEC_PRE_DOUBLE:-}"

# We make another prehook so that `PATH=<OPAMHOME>/bin:"$PATH"` at the beginning of all the hooks.
# That way `opam` will work including from any child processes that opam spawns.
if [ -n "$OPAMHOME" ]; then
    if [ ! -x "$OPAMHOME/bin/opam" ] && [ ! -x "$OPAMHOME/bin/opam.exe" ]; then
        printf "FATAL: The OPAMHOME='%s' does not have a bin/opam or bin/opam.exe\n" "$OPAMHOME" >&2
        exit 107
    fi
    {
        printf "PATH='%s'/bin:\"\$PATH\"\n" "$OPAMHOME"
        if [ -n "$PLATFORM_EXEC_PRE_SINGLE" ]; then
            printf "\n"
            cat "$PLATFORM_EXEC_PRE_SINGLE"
            printf "\n"
        fi
    } > "$WORK"/platform-opam-exec.sh.opamhome.prehook.source.sh
    # shellcheck disable=SC2034
    PLATFORM_EXEC_PRE_SINGLE="$WORK"/platform-opam-exec.sh.opamhome.prehook.source.sh
fi
# Ditto for `ocaml`
if [ -n "$OCAMLVERSION_OR_HOME" ]; then
    if [ -x /usr/bin/cygpath ]; then
        # If OCAMLVERSION_OR_HOME=C:/x/y/z then match against /c/x/y/z
        OCAMLVERSION_OR_HOME_UNIX=$(/usr/bin/cygpath -u "$OCAMLVERSION_OR_HOME")
    else
        OCAMLVERSION_OR_HOME_UNIX="$OCAMLVERSION_OR_HOME"
    fi
    case "$OCAMLVERSION_OR_HOME_UNIX" in
        /* | ?:*) # /a/b/c or C:\Windows
            validate_and_explore_ocamlhome "$OCAMLVERSION_OR_HOME"
            {
                printf "PATH='%s':\"\$PATH\"\n" "$DKML_OCAMLHOME_UNIX/$DKML_OCAMLHOME_BINDIR_UNIX"
                if [ -n "$PLATFORM_EXEC_PRE_SINGLE" ]; then
                    printf "\n"
                    cat "$PLATFORM_EXEC_PRE_SINGLE"
                    printf "\n"
                fi
            } > "$WORK"/platform-opam-exec.sh.ocamlhome.prehook.source.sh
            # shellcheck disable=SC2034
            PLATFORM_EXEC_PRE_SINGLE="$WORK"/platform-opam-exec.sh.ocamlhome.prehook.source.sh
        ;;
    esac
fi

# -----------------------
# Inject our options first, immediately after the subcommand

set +u # workaround bash 'unbound variable' triggered on empty arrays
case "$subcommand" in
    help)
        exec_in_platform "$OPAMEXE" help "$@"
    ;;
    init)
        exec_in_platform "$OPAMEXE" init --root "$OPAMROOTDIR_EXPAND" "${OPAM_OPTS[@]}" "$@"
    ;;
    list | option | repository | env)
        exec_in_platform "$OPAMEXE" "$subcommand" "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
    ;;
    switch)
        if [ "$1" = create ]; then
            # When a switch is created we need a commpiler
            exec_in_platform -c "$OPAMEXE" "$subcommand" "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
        else
            exec_in_platform "$OPAMEXE" "$subcommand" "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
        fi
    ;;
    install | upgrade | pin)
        # FYI: `pin add` and probably other pin commands can (re-)install packages, so compiler is needed
        if [ "$DISKUV_TOOLS_SWITCH" = ON ]; then
            # When we are upgrading / installing a package in the host tools switch, we must have a compiler so we can compile
            # with-dkml.exe
            exec_in_platform -c "$OPAMEXE" "$subcommand" "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
        else
            # When we are upgrading / installing a package in any other switch, we will have a with-dkml.exe wrapper to
            # provide the compiler
            exec_in_platform "$OPAMEXE" "$subcommand" "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
        fi
    ;;
    exec)
        # The wrapper set in wrapper-{build|remove|install}-commands is only automatically used within `opam install`
        # and `opam remove`. So we directly use it here.
        # There are edge cases during Windows installation/upgrade (setup-userprofile.ps1):
        # 1. dkmlvars.sexp will not exist until the very end of a successful install; we do _not_ use the wrapper since it
        #    will fail without dkmlvars.sexp (or worse, it will use an _old_ dkmlvars.sexp).
        # 2. When compiling with-dkml.exe itself, we do not want to use an old with-dkml.exe (or any with-dkml.exe) to do
        #    so, even if it mostly harmless
        if [ -e "$WITHDKMLEXE_BUILDHOST" ] && [ "${WITHDKML_ENABLE:-ON}" = ON ]; then
            if [ "$1" = "--" ]; then
                shift
                exec_in_platform "$OPAMEXE" exec "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" -- "$WITHDKMLEXE_BUILDHOST" "$@"
            else
                exec_in_platform "$OPAMEXE" exec "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$WITHDKMLEXE_BUILDHOST" "$@"
            fi
        else
            # Since we do not yet have with-dkml.exe (ie. we are in the middle of a new installation / upgrade), supply the compiler as an
            # alternative so `opam exec -- dune build` works
            exec_in_platform -c "$OPAMEXE" exec "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
        fi
    ;;
    *)
        exec_in_platform "$OPAMEXE" "$subcommand" "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
    ;;
esac
