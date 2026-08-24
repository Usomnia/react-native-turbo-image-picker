cmake_minimum_required(VERSION 3.13.4 FATAL_ERROR)
set(CMAKE_VERBOSE_MAKEFILE ON)

project(react_codegen_RNTurboImagePickerSpec)

set(GENERATED_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/generated/source/codegen/jni")

if(NOT COMMAND target_compile_reactnative_options)
    macro(target_compile_reactnative_options target scope)
        # Standalone build fail 방지용 더미 (RN 전역 룰이 없을 땐 무시)
    endmacro()
endif()
if(EXISTS "${GENERATED_SRC_DIR}/CMakeLists.txt")
    message(STATUS "RNTurboImagePicker: Found codegen CMakeLists.txt at ${GENERATED_SRC_DIR}")
    add_subdirectory("${GENERATED_SRC_DIR}" "codegen_RNTurboImagePickerSpec")
    
    # React Native 0.74 Codegen 버그(타겟명이 AppSpecs로 고정되는 문제) 우회
    if(TARGET react_codegen_AppSpecs AND NOT TARGET react_codegen_RNTurboImagePickerSpec)
        message(STATUS "RNTurboImagePicker: Bridging react_codegen_AppSpecs -> react_codegen_RNTurboImagePickerSpec")
        add_library(react_codegen_RNTurboImagePickerSpec INTERFACE)
        target_link_libraries(react_codegen_RNTurboImagePickerSpec INTERFACE react_codegen_AppSpecs)
    endif()
else()
    message(WARNING "RNTurboImagePicker: Codegen CMakeLists.txt NOT FOUND! Dummy library will be used to prevent crash.")
    # 앱의 링킹 오류를 방지하기 위해 더미 타겟 생성
    add_library(react_codegen_RNTurboImagePickerSpec SHARED)
    
    # 더미 소스 생성
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/dummy.cpp" "void dummy_RNTurboImagePickerSpec() {}")
    target_sources(react_codegen_RNTurboImagePickerSpec PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/dummy.cpp")
endif()
