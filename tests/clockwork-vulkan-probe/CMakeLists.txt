cmake_minimum_required(VERSION 3.22.1)
project(ForgeClockworkVulkanProbe LANGUAGES C CXX)

set(CLOCKWORK_SOURCE_DIR "$ENV{CLOCKWORK_SOURCE_DIR}" CACHE PATH "Clockwork checkout")
set(CLOCKWORK_EXPECTED_REVISION "c5e5a9a6362c35512823884753d2d5284af204fa" CACHE STRING
    "Clockwork revision for the historical compatibility probe")
if (NOT EXISTS "${CLOCKWORK_SOURCE_DIR}/cmake/OpenMWVulkan.cmake")
    message(FATAL_ERROR "CLOCKWORK_SOURCE_DIR must name the pinned Clockwork checkout")
endif()
execute_process(
    COMMAND git -C "${CLOCKWORK_SOURCE_DIR}" rev-parse HEAD
    RESULT_VARIABLE revision_result
    OUTPUT_VARIABLE actual_revision
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
if (NOT revision_result EQUAL 0 OR NOT "${actual_revision}" STREQUAL "${CLOCKWORK_EXPECTED_REVISION}")
    message(FATAL_ERROR
        "Clockwork checkout must be ${CLOCKWORK_EXPECTED_REVISION}; got '${actual_revision}'")
endif()

set(OPENMW_USE_VULKAN ON CACHE BOOL "" FORCE)
set(OPENMW_USE_SYSTEM_GLSLANG OFF CACHE BOOL "" FORCE)
set(OPENMW_USE_SYSTEM_VULKAN_HEADERS OFF CACHE BOOL "" FORCE)
set(OPENMW_USE_SYSTEM_VMA OFF CACHE BOOL "" FORCE)
set(OPENMW_GLSLANG_MINIMUM 15.1)
set(OPENMW_VULKAN_HEADERS_MINIMUM 1.4.335)

include("${CLOCKWORK_SOURCE_DIR}/cmake/OpenMWVulkan.cmake")
openmw_configure_vulkan()

include(FetchContent)
FetchContent_Declare(vma
    URL https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator/archive/refs/tags/v3.4.0.zip
    URL_HASH SHA512=f32821ee0fe7e56743dbea9b16716d686ea12b25cc7eebe1f43eb1d6faee910ff4f76fca8b1a9d1ab84b4ba281df10be91ac085c0ba2caae593ff55476dcdb16
    SOURCE_DIR ${CMAKE_BINARY_DIR}/extern/fetched/vma
    SOURCE_SUBDIR include
)
FetchContent_MakeAvailable(vma)
if (NOT EXISTS "${vma_SOURCE_DIR}/include/vk_mem_alloc.h")
    message(FATAL_ERROR "Pinned VMA header was not fetched")
endif()

if (NOT OPENMW_USE_VULKAN)
    message(FATAL_ERROR "OPENMW_USE_VULKAN was silently disabled")
endif()
if (NOT TARGET glslang::glslang OR NOT TARGET glslang::SPIRV)
    message(FATAL_ERROR "Clockwork's pinned glslang targets are unavailable")
endif()
if (NOT TARGET Vulkan::Vulkan)
    message(FATAL_ERROR "Vulkan loader import target is unavailable")
endif()
if (NOT EXISTS "${OPENMW_VULKAN_REGISTRY}")
    message(FATAL_ERROR "Clockwork's Vulkan XML registry is unavailable")
endif()

add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/devicetable.cpp"
    COMMAND Python3::Interpreter -I
        "${CLOCKWORK_SOURCE_DIR}/components/vulkan/devicetable.py"
        "${OPENMW_VULKAN_REGISTRY}" "${CMAKE_BINARY_DIR}/devicetable.cpp"
    DEPENDS "${CLOCKWORK_SOURCE_DIR}/components/vulkan/devicetable.py"
        "${OPENMW_VULKAN_REGISTRY}"
)
add_custom_target(clockwork_device_table ALL DEPENDS "${CMAKE_BINARY_DIR}/devicetable.cpp")

add_executable(clockwork_vulkan_link_probe vulkan_link_probe.cpp)
target_include_directories(clockwork_vulkan_link_probe PRIVATE "${vma_SOURCE_DIR}/include")
target_link_libraries(clockwork_vulkan_link_probe PRIVATE Vulkan::Vulkan)

message(STATUS "QUALIFIED OPENMW_USE_VULKAN=${OPENMW_USE_VULKAN}")
message(STATUS "QUALIFIED glslang_VERSION=${glslang_VERSION}")
message(STATUS "QUALIFIED Vulkan_VERSION=${Vulkan_VERSION}")
message(STATUS "QUALIFIED Vulkan_LIBRARY=${Vulkan_LIBRARY}")
message(STATUS "QUALIFIED OPENMW_VULKAN_REGISTRY=${OPENMW_VULKAN_REGISTRY}")
message(STATUS "QUALIFIED VMA_SOURCE_DIR=${vma_SOURCE_DIR}")
