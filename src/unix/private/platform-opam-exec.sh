#!/bin/bash
# -------------------------------------------------------
# platform-opam-exec.sh [-s | -p DKMLABI] [--] install|clean|help|...
#
# DKMLABI=linux_arm32v6|linux_arm32v7|windows_x86|...
# -------------------------------------------------------
set -euf

DKMLDIR=$(dirname "$0")
DKMLDIR=$(cd "$DKMLDIR"/../../../../.. && pwd)

# shellcheck disable=SC1091
. "$DKMLDIR/vendor/drc/unix/crossplatform-functions.sh"

# ------------------
# BEGIN Command line processing

usage() {
    printf "%s\n" "Usage:" >&2
    printf "%s\n" "    platform-opam-exec.sh -h                                     Display this help message" >&2
    printf "%s\n" "    platform-opam-exec.sh -p DKMLABI [-b]" >&2
    printf "%s\n" "                          [--] dkml|...                          Run the opam command with no Opam root selected" >&2
    printf "%s\n" "                                                                 and no switch selected" >&2
    printf "%s\n" "    platform-opam-exec.sh -p DKMLABI" >&2
    printf "%s\n" "                          [--] var|clean|help|...                Run the opam command with the user Opam root" >&2
    printf "%s\n" "                                                                 without any switch selected" >&2
    printf "%s\n" "    platform-opam-exec.sh -p DKMLABI (-s|-n GLOBALOPAMSWITCH|-t LOCALOPAMSWITCH)" >&2
    printf "%s\n" "                          [--] install|clean|help|...            Run the opam command with the user Opam root" >&2
    printf "%s\n" "                                                                 in the global [dkml] switch (if -s) or the" >&2
    printf "%s\n" "                                                                 global GLOBALOPAMSWITCH switch or the local" >&2
    printf "%s\n" "                                                                 LOCALOPAMSWITCH switch" >&2
    printf "%s\n" "    platform-opam-exec.sh -p DKMLABI (-d STATEDIR|-r OPAMROOT)" >&2
    printf "%s\n" "                          [--] var|clean|help|...                Run the opam command with the Opam root" >&2
    printf "%s\n" "                                                                 OPAMROOT or STATEDIR/opam without any Opam switch" >&2
    printf "%s\n" "                                                                 selected" >&2
    printf "%s\n" "    platform-opam-exec.sh -p DKMLABI (-d STATEDIR|-r OPAMROOT) (-s|-n GLOBALOPAMSWITCH|-t LOCALOPAMSWITCH)" >&2
    printf "%s\n" "                          [--] install|clean|help|...            Run the opam command with the Opam root" >&2
    printf "%s\n" "                                                                 OPAMROOT or STATEDIR/opam in the global [dkml] switch (if -s)" >&2
    printf "%s\n" "                                                                 or the global GLOBALOPAMSWITCH switch or the" >&2
    printf "%s\n" "                                                                 local LOCALOPAMSWITCH switch" >&2
    printf "%s\n" "" >&2
    printf "%s\n" "Opam root directory:" >&2
    printf "%s\n" "    If -r OPAMROOT then <OPAMROOT> is the Opam root directory." >&2
    printf "%s\n" "    Or if -d STATEDIR then <STATEDIR>/opam is the Opam root directory." >&2
    printf "%s\n" "    Otherwise the Opam root directory is the user's standard Opam root directory." >&2
    printf "%s\n" "    It is an error for both [-r] and [-d] to be specified" >&2
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
    printf "%s\n" "    -p DKMLABI: The DKML ABI (not 'dev')" >&2
    printf "%s\n" "    -b: No Opam root will be used. No Opam switch will be used." >&2
    printf "%s\n" "    -a: Do not look for with-dkml. By default with-dkml is searched for and then added to the PATH." >&2
    printf "%s\n" "    -s: Select the [dkml] switch. If specified adds --switch to opam, and implies -x option" >&2
    printf "%s\n" "    -n GLOBALOPAMSWITCH: The target global Opam switch. If specified adds --switch to opam" >&2
    printf "%s\n" "    -t LOCALOPAMSWITCH: The target Opam switch. If specified adds --switch to opam." >&2
    printf "%s\n" "       Usability enhancement: Opam init shell scripts search the ancestor paths for an" >&2
    printf "%s\n" "       '_opam' directory, so the local switch will be found if you are in <LOCALOPAMSWITCH>" >&2
    printf "%s\n" "    -r OPAMROOT: Use <OPAMROOT> as the Opam root" >&2
    printf "%s\n" "    -d STATEDIR: Use <STATEDIR>/opam as the Opam root directory" >&2
    printf "%s\n" "    -u ON|OFF: Deprecated" >&2
    printf "%s\n" "    -o OPAMEXE_OR_HOME: Optional. If a directory, it is the home for Opam containing bin/opam-real or bin/opam." >&2
    printf "%s\n" "       If it is a directory, the bin/ subdir of the Opam home is added to the PATH." >&2
    printf "%s\n" "       If an executable, it is the opam to use (and when there is an opam shim the opam-real can be used)." >&2
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
DKMLABI=
DKML_TOOLS_SWITCH=OFF
DKML_OPAM_ROOT=
STATEDIR=
PREHOOK_SINGLE_EVAL=
PREHOOK_DOUBLE_EVAL=
TARGETLOCAL_OPAMSWITCH=
TARGETGLOBAL_OPAMSWITCH=
OPAMEXE_OR_HOME=
OCAMLVERSION_OR_HOME=
USE_ROOT=ON
NO_WITHDKML=OFF
while getopts ":h0:1:p:sn:t:d:r:u:o:v:ba" opt; do
    case ${opt} in
        h )
            usage
            exit 0
        ;;
        p )
            DKMLABI=$OPTARG
            if [ "$DKMLABI" = dev ]; then
                usage
                exit 0
            fi
        ;;
        d ) STATEDIR=$OPTARG ;;
        r ) DKML_OPAM_ROOT=$OPTARG ;;
        u ) true ;;
        b ) USE_ROOT=OFF ;;
        s ) DKML_TOOLS_SWITCH=ON ;;
        a ) NO_WITHDKML=ON ;;
        n ) TARGETGLOBAL_OPAMSWITCH=$OPTARG ;;
        t ) TARGETLOCAL_OPAMSWITCH=$OPTARG ;;
        o ) OPAMEXE_OR_HOME=$OPTARG ;;
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

if [ -z "${DKMLABI:-}" ]; then
    echo "FATAL: Missing -p DKMLABI option" >&2
    usage
    exit 1
fi
if [ -n "$STATEDIR" ] && [ -n "$DKML_OPAM_ROOT" ]; then
    printf "%s\n" "Both -d and -r cannot be specified at the same time" >&2
    usage
    exit 1
fi

#   At most one of -t LOCALOPAMSWITCH, -s, -n GLOBALOPAMSWITCH
_switch_count=
if [ "$DKML_TOOLS_SWITCH" = ON ]; then _switch_count="x$_switch_count"; fi
if [ -n "$TARGETLOCAL_OPAMSWITCH" ]; then _switch_count="x$_switch_count"; fi
if [ -n "$TARGETGLOBAL_OPAMSWITCH" ]; then _switch_count="x$_switch_count"; fi
if [ -z "$_switch_count" ]; then
    USE_SWITCH=OFF
elif [ "$_switch_count" = x ]; then
    USE_SWITCH=ON
else
    echo "FATAL: At most one of -t LOCALOPAMSWITCH, -s, -n GLOBALOPAMSWITCH may be specified" >&2
    usage
    exit 1
fi

#   The switches cannot be used with -b
if [ "$USE_SWITCH" = ON ] && [ "$USE_ROOT" = OFF ]; then
    echo "FATAL: Cannot use -t LOCALOPAMSWITCH, -s or -n GLOBALOPAMSWITCH with the -b option" >&2
    usage
    exit 1
fi

if [ "${1:-}" = "--" ]; then # supports `platform-opam-exec.sh ... -- --version`
    shift
fi

# END Command line processing
# ------------------

# Win32 conversions
if [ -x /usr/bin/cygpath ]; then
    if [ -n "$OPAMEXE_OR_HOME" ]; then OPAMEXE_OR_HOME=$(/usr/bin/cygpath -am "$OPAMEXE_OR_HOME"); fi
fi

# shellcheck disable=SC1091
. "$DKMLDIR"/vendor/drc/unix/_common_tool.sh

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

# Clean opam environment. Everything that influences opam should come from a
# [platform-opam-exec] command line option so it is reproducible.
export OPAMROOT=
export OPAMSWITCH=
export OPAM_SWITCH_PREFIX=

# ------------
# BEGIN --root

# Set OPAMEXE from OPAMEXE_OR_HOME
set_opamexe

OPAM_ROOT_OPT=() # we have a separate array for --root since --root is mandatory for `opam init`
if [ "$USE_ROOT" = ON ]; then
    # Set OPAMROOTDIR_BUILDHOST and OPAMROOTDIR_EXPAND (from DKML_OPAM_ROOT and/or STATEDIR if set)
    set_opamrootdir

    # We check if the root exists before we add --root
    if is_minimal_opam_root_present "$OPAMROOTDIR_BUILDHOST"; then
        OPAM_ROOT_OPT+=( --root "$OPAMROOTDIR_EXPAND" )
        if [ "$USE_SWITCH" = ON ]; then
            # `--set-switch` will output the globally selected switch, if any.
            OPAM_ENV_STMT="'$OPAMEXE'"' env --quiet --root "'$OPAMROOTDIR_EXPAND'" --set-root --set-switch || true'
        else
            OPAM_ENV_STMT="'$OPAMEXE'"' env --quiet --root "'$OPAMROOTDIR_EXPAND'" --set-root || true'
        fi
    fi
fi

# END --root
# ------------

# ------------
# BEGIN --switch

if [ "$USE_SWITCH" = ON ]; then

    # Set $DKMLHOME_UNIX, $DKMLPARENTHOME_BUILDHOST and other vars
    autodetect_dkmlvars || true

    # Q: What if there was no switch but there was a root?
    # Ans: This section would be skipped, and the earlier `opam env --root yyy --set-root` would have captured the environment with its OPAM_ENV_STMT.

    # The `dkml` switch will have the with-dkml.exe binary which is used by non-`dkml`
    # switches. Whether the `dkml` switch is being created or being used, we need
    # to know where it is or where it will be.
    #   Set OPAMSWITCHFINALDIR_BUILDHOST, OPAMSWITCHNAME_EXPAND of `dkml` switch
    #   and set OPAMROOTDIR_BUILDHOST, OPAMROOTDIR_EXPAND
    set_opamswitchdir_of_system "$DKMLABI"

    # Now we need the specified switch's OPAMSWITCHFINALDIR_BUILDHOST and OPAMSWITCHNAME_EXPAND
    if [ "$DKML_TOOLS_SWITCH" = ON ]; then
        # Already set in set_opamswitchdir_of_system
        true

        # Unset WITHDKMLEXE_BUILDHOST (if any)
        unset WITHDKMLEXE_BUILDHOST
    else
        # Set OPAMROOTDIR_BUILDHOST, OPAMROOTDIR_EXPAND, OPAMSWITCHFINALDIR_BUILDHOST, OPAMSWITCHNAME_EXPAND
        set_opamrootandswitchdir "$TARGETLOCAL_OPAMSWITCH" "$TARGETGLOBAL_OPAMSWITCH"

        # Set WITHDKMLEXE_BUILDHOST (or unset it)
        if [ "$NO_WITHDKML" = ON ]; then
            unset WITHDKMLEXE_BUILDHOST
        else
            autodetect_withdkmlexe
        fi
    fi

    # We check if the switch exists before we add --switch. Otherwise `opam` will complain:
    #   [ERROR] The selected switch C:/source/xxx/build/dev/Debug is not installed.
    if {
        [ -n "${OPAMSWITCHFINALDIR_BUILDHOST:-}" ] &&
        [ -n "${OPAMSWITCHNAME_EXPAND:-}" ] &&
        is_minimal_opam_switch_present "$OPAMSWITCHFINALDIR_BUILDHOST" 
    }; then
        OPAM_OPTS+=( --switch "$OPAMSWITCHNAME_EXPAND" )
        OPAM_ENV_STMT="'$OPAMEXE'"' env --quiet --root "'$OPAMROOTDIR_EXPAND'" --switch "'$OPAMSWITCHNAME_EXPAND'" --set-root --set-switch || true'
    fi
fi # [ "$USE_SWITCH" = ON ]

# END --switch
# ------------

# We'll make a prehook so that `opam env --root yyy [--switch zzz] --set-root [--set-switch]` is automatically executed.
# We compose prehooks by letting user-specified prehooks override our own. So user-specified prehooks go last so they can override the environment.
if [ -n "${PLATFORM_EXEC_PRE_DOUBLE:-}" ]; then PLATFORM_EXEC_PRE_DOUBLE="; $PLATFORM_EXEC_PRE_DOUBLE"; fi
# shellcheck disable=SC2034 disable=SC2016
PLATFORM_EXEC_PRE_DOUBLE="${OPAM_ENV_STMT:-} ${PLATFORM_EXEC_PRE_DOUBLE:-}"

# We make another prehook to set the TEMP and TMPDIR environment variables.
export_safe_tmpdir
{
    printf "TMPDIR='%s'\n" "$TMPDIR"
    printf "TEMP='%s'\n" "$TEMP"
    if [ -n "$PLATFORM_EXEC_PRE_SINGLE" ]; then
        printf "\n"
        cat "$PLATFORM_EXEC_PRE_SINGLE"
        printf "\n"
    fi
} > "$WORK"/platform-opam-exec.sh.opamhome.prehook1.source.sh
# shellcheck disable=SC2034
PLATFORM_EXEC_PRE_SINGLE="$WORK"/platform-opam-exec.sh.opamhome.prehook1.source.sh

# We make another prehook so that `PATH=<OPAMHOME>/bin:"$PATH"` at the beginning of all the hooks.
# That way `opam-real` or `opam` will work including from any child processes that opam spawns.
if [ -n "$OPAMEXE_OR_HOME" ] && [ -d "$OPAMEXE_OR_HOME" ]; then
    OPAMEXEDIR=$(dirname "$OPAMEXE_OR_HOME")
    {
        printf "PATH='%s':\"\$PATH\"\n" "$OPAMEXEDIR"
        if [ -n "$PLATFORM_EXEC_PRE_SINGLE" ]; then
            printf "\n"
            cat "$PLATFORM_EXEC_PRE_SINGLE"
            printf "\n"
        fi
    } > "$WORK"/platform-opam-exec.sh.opamhome.prehook2.source.sh
    # shellcheck disable=SC2034
    PLATFORM_EXEC_PRE_SINGLE="$WORK"/platform-opam-exec.sh.opamhome.prehook2.source.sh
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
                printf "PATH='%s':\"\$PATH\"\n" "$DKML_OCAMLHOME_ABSBINDIR_UNIX"
                if [ -n "$PLATFORM_EXEC_PRE_SINGLE" ]; then
                    printf "\n"
                    cat "$PLATFORM_EXEC_PRE_SINGLE"
                    printf "\n"
                fi
            } > "$WORK"/platform-opam-exec.sh.ocamlhome.prehook3.source.sh
            # shellcheck disable=SC2034
            PLATFORM_EXEC_PRE_SINGLE="$WORK"/platform-opam-exec.sh.ocamlhome.prehook3.source.sh
        ;;
    esac
fi

# -----------------------
# Inject our options first, immediately after the subcommand

set +u # workaround bash 'unbound variable' triggered on empty arrays
case "$subcommand" in
    help)
        exec_in_platform "$DKMLABI" "$OPAMEXE" help "$@"
    ;;
    init)
        exec_in_platform "$DKMLABI" "$OPAMEXE" init --root "$OPAMROOTDIR_EXPAND" "${OPAM_OPTS[@]}" "$@"
    ;;
    list | option | repository | env)
        exec_in_platform "$DKMLABI" "$OPAMEXE" "$subcommand" "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
    ;;
    switch)
        if [ "$1" = create ]; then
            # When a switch is created we need a commpiler
            exec_in_platform -c "$DKMLABI" "$OPAMEXE" "$subcommand" "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
        else
            exec_in_platform "$DKMLABI" "$OPAMEXE" "$subcommand" "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
        fi
    ;;
    install | upgrade | pin)
        # FYI: `pin add` and probably other pin commands can (re-)install packages, so compiler is needed
        if [ "$DKML_TOOLS_SWITCH" = ON ]; then
            # When we are upgrading / installing a package in the host tools switch, we must have a compiler so we can compile
            # with-dkml.exe
            exec_in_platform -c "$DKMLABI" "$OPAMEXE" "$subcommand" "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
        else
            # When we are upgrading / installing a package in any other switch, we will have a with-dkml.exe wrapper to
            # provide the compiler
            exec_in_platform "$DKMLABI" "$OPAMEXE" "$subcommand" "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
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
        if [ "$USE_SWITCH" = OFF ]; then
            # There is no switch in use. So don't need with-dkml.exe nor do we need a C compiler.
            exec_in_platform "$DKMLABI" "$OPAMEXE" exec "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
        elif [ "${WITHDKML_ENABLE:-ON}" = ON ] && [ -n "${WITHDKMLEXE_BUILDHOST:-}" ] && [ -e "$WITHDKMLEXE_BUILDHOST" ]; then
            if [ "$1" = "--" ]; then
                shift
                exec_in_platform "$DKMLABI" "$OPAMEXE" exec "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" -- "$WITHDKMLEXE_BUILDHOST" "$@"
            else
                exec_in_platform "$DKMLABI" "$OPAMEXE" exec "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$WITHDKMLEXE_BUILDHOST" "$@"
            fi            
        else
            # We were asked to use a switch. But we do not yet have with-dkml.exe
            # (ie. we are in the middle of a new installation / upgrade), so supply
            # the compiler as an alternative so `opam exec -- dune build` (etc.) works
            exec_in_platform -c "$DKMLABI" "$OPAMEXE" exec "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
        fi
    ;;
    *)
        exec_in_platform "$DKMLABI" "$OPAMEXE" "$subcommand" "${OPAM_ROOT_OPT[@]}" "${OPAM_OPTS[@]}" "$@"
    ;;
esac
