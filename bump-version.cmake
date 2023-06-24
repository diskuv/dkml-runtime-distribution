if(NOT GIT_EXECUTABLE)
    message(FATAL_ERROR "Missing -D GIT_EXECUTABLE=xx")
endif()

if(NOT DKML_VERSION_SEMVER)
    message(FATAL_ERROR "Missing -D DKML_VERSION_SEMVER=xx")
endif()

if(NOT DKML_VERSION_SEMVER_NEW)
    message(FATAL_ERROR "Missing -D DKML_VERSION_SEMVER_NEW=xx")
endif()

function(plain_replace REL_FILENAME)
    file(READ ${REL_FILENAME} contents)
    string(REPLACE "${DKML_VERSION_SEMVER}" "${DKML_VERSION_SEMVER_NEW}"
        contents_NEW
        "${contents}")

    if(contents STREQUAL "${contents_NEW}")
        cmake_path(ABSOLUTE_PATH REL_FILENAME OUTPUT_VARIABLE FILENAME_ABS)
        message(FATAL_ERROR "The old version ${DKML_VERSION_SEMVER} was not found in ${FILENAME_ABS}")
    endif()

    file(WRITE ${REL_FILENAME} "${contents_NEW}")

    message(NOTICE "Bumped ${REL_FILENAME} to ${DKML_VERSION_SEMVER_NEW}")
endfunction(plain_replace)

plain_replace(README.md)

execute_process(
    COMMAND
    ${GIT_EXECUTABLE} add README.md
    COMMAND_ERROR_IS_FATAL ANY
)
execute_process(
    COMMAND
    ${GIT_EXECUTABLE} commit -m "Bump version: ${DKML_VERSION_SEMVER} → ${DKML_VERSION_SEMVER_NEW_PRERELEASE}"
)