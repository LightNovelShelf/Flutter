cmake_minimum_required(VERSION 3.20)
project(lightnovel_native LANGUAGES C CXX)

include(FetchContent)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)

FetchContent_Declare(
  brotli
  GIT_REPOSITORY https://github.com/google/brotli.git
  GIT_TAG 533843e3546cd24c8344eaa899c6b0b681c8d222
  GIT_SHALLOW FALSE
  SOURCE_SUBDIR _lightnovel_no_cmake
)
FetchContent_Declare(
  woff2
  GIT_REPOSITORY https://github.com/google/woff2.git
  GIT_TAG fb9c3379f2605b10f3e8f1d9636664ab5576775c
  GIT_SHALLOW FALSE
  SOURCE_SUBDIR _lightnovel_no_cmake
)
FetchContent_MakeAvailable(brotli woff2)


add_library(brotli_decoder STATIC
  ${brotli_SOURCE_DIR}/c/common/dictionary.c
  ${brotli_SOURCE_DIR}/c/common/transform.c
  ${brotli_SOURCE_DIR}/c/dec/bit_reader.c
  ${brotli_SOURCE_DIR}/c/dec/decode.c
  ${brotli_SOURCE_DIR}/c/dec/huffman.c
  ${brotli_SOURCE_DIR}/c/dec/state.c
)
target_include_directories(brotli_decoder PUBLIC ${brotli_SOURCE_DIR}/c/include)
target_compile_definitions(brotli_decoder PRIVATE BROTLI_BUILD_PORTABLE)

add_library(woff2_decoder SHARED
  ${woff2_SOURCE_DIR}/src/table_tags.cc
  ${woff2_SOURCE_DIR}/src/variable_length.cc
  ${woff2_SOURCE_DIR}/src/woff2_common.cc
  ${woff2_SOURCE_DIR}/src/woff2_dec.cc
  ${woff2_SOURCE_DIR}/src/woff2_out.cc
  src/woff2_bridge.cc
)
set_target_properties(woff2_decoder PROPERTIES OUTPUT_NAME woff2)
target_include_directories(woff2_decoder PUBLIC
  ${woff2_SOURCE_DIR}/include
  ${woff2_SOURCE_DIR}/src
)
target_link_libraries(woff2_decoder PRIVATE brotli_decoder)

add_library(lightnovel_native SHARED src/blurhash.cc)
set_target_properties(lightnovel_native PROPERTIES OUTPUT_NAME lightnovel_native)
target_compile_options(lightnovel_native PRIVATE
  $<$<CXX_COMPILER_ID:Clang,GNU>:-Wall;-Wextra;-Werror>
  $<$<CXX_COMPILER_ID:MSVC>:/W4;/WX>
)

if(UNIX AND NOT APPLE)
  target_link_libraries(lightnovel_native PRIVATE m)
  target_link_libraries(woff2_decoder PRIVATE m)
endif()

if(APPLE)
  set_target_properties(lightnovel_native woff2_decoder PROPERTIES
    BUILD_WITH_INSTALL_NAME_DIR ON
    INSTALL_NAME_DIR "@rpath"
  )
endif()

if(WIN32)
  set_target_properties(lightnovel_native woff2_decoder PROPERTIES PREFIX "")
  if(MINGW)
    foreach(target lightnovel_native woff2_decoder)
      target_link_options(${target} PRIVATE -static-libgcc -static-libstdc++)
    endforeach()
  endif()
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Release")
  foreach(target lightnovel_native woff2_decoder)
    if(APPLE)
      target_link_options(${target} PRIVATE -Wl,-S,-x)
    elseif(NOT MSVC)
      target_link_options(${target} PRIVATE -Wl,--strip-all)
    endif()
  endforeach()
endif()

if(DEFINED LN_OUTPUT_DIR)
  foreach(target lightnovel_native woff2_decoder)
    set_target_properties(${target} PROPERTIES
      LIBRARY_OUTPUT_DIRECTORY "${LN_OUTPUT_DIR}"
      RUNTIME_OUTPUT_DIRECTORY "${LN_OUTPUT_DIR}"
    )
  endforeach()
endif()
