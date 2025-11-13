cmake_minimum_required(VERSION 3.20)
project(uv VERSION 0.9.9)

set(EXTRACT_DIR "${CMAKE_BINARY_DIR}/extracted")

add_custom_target(extract_archive ALL
    COMMAND ${CMAKE_COMMAND} -E tar xzf "${CMAKE_SOURCE_DIR}/uv-x86_64-unknown-linux-gnu.tar.gz"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_BINARY_DIR}/uv-x86_64-unknown-linux-gnu" "${EXTRACT_DIR}"
    COMMENT "Extracting uv archive"
)

install(PROGRAMS "${EXTRACT_DIR}/uv" "${EXTRACT_DIR}/uvx" DESTINATION bin)

set(CPACK_GENERATOR "DEB")
set(CPACK_PACKAGE_CONTACT "uv Package Maintainer <maintainer@example.com>")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "An extremely fast Python package installer and resolver")
set(CPACK_PACKAGE_DESCRIPTION "uv is a fast Python package installer and resolver written in Rust.")
set(CPACK_DEBIAN_PACKAGE_SECTION "devel")
set(CPACK_DEBIAN_PACKAGE_PRIORITY "optional")
set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "amd64")
set(CPACK_DEBIAN_PACKAGE_CONTROL_EXTRA "${CMAKE_SOURCE_DIR}/debian/prerm")

include(CPack)
