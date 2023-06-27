# The OPAMROOT and OPAMSWITCH variables must be set to the switch to copy from, and
# the 'opam' executable must be in the PATH.
#
# Test with:
# cmake --log-context -D DRYRUN=1 -D CMAKE_MESSAGE_CONTEXT=dkml-runtime-distribution -D DKML_RELEASE_IS_UPGRADING_PACKAGES=1 -D GIT_EXECUTABLE=git -D DKML_RELEASE_DUNE_VERSION=3.6.2 -D DKML_RELEASE_PARTICIPANT_MODULE=../../../packaging/version-bump/DkMLReleaseParticipant.cmake -P bump-packages.cmake

if(NOT DKML_RELEASE_PARTICIPANT_MODULE)
    message(FATAL_ERROR "Missing -D DKML_RELEASE_PARTICIPANT_MODULE=.../DkMLReleaseParticipant.cmake")
endif()
include(${DKML_RELEASE_PARTICIPANT_MODULE})

DkMLReleaseParticipant_CreateOpamSwitchUpgrade(src/unix/create-opam-switch.sh)
DkMLReleaseParticipant_GitAddAndCommit()
