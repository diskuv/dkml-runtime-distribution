# Test with:
# cmake --log-context -D DRYRUN=1 -D CMAKE_MESSAGE_CONTEXT=dkml-runtime-distribution -D "regex_DKML_VERSION_SEMVER=1[.]2[.]1-[0-9]+" -D "regex_DKML_VERSION_OPAMVER=1[.]2[.]1[~]prerel[0-9]+" -D DKML_VERSION_SEMVER_NEW=1.2.1-3 -D DKML_VERSION_OPAMVER_NEW=1.2.1~prerel3 -D GIT_EXECUTABLE=git -D DKML_RELEASE_OCAML_VERSION=4.14.0 -D DKML_RELEASE_PARTICIPANT_MODULE=../../../pkg/bump/DkMLReleaseParticipant.cmake -P bump-version.cmake

if(NOT DKML_RELEASE_PARTICIPANT_MODULE)
    message(FATAL_ERROR "Missing -D DKML_RELEASE_PARTICIPANT_MODULE=.../DkMLReleaseParticipant.cmake")
endif()
include(${DKML_RELEASE_PARTICIPANT_MODULE})

DkMLReleaseParticipant_PlainReplace(README.md)
DkMLReleaseParticipant_OpamReplace(dkml-runtime-distribution.opam)
DkMLReleaseParticipant_PkgsReplace(src/none/ci-${DKML_RELEASE_OCAML_VERSION}-pkgs.txt)
DkMLReleaseParticipant_CreateOpamSwitchReplace(src/unix/create-opam-switch.sh)
DkMLReleaseParticipant_DuneProjectReplace(dune-project)
DkMLReleaseParticipant_GitAddAndCommit()
