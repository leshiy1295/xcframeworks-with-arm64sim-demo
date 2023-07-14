#!/bin/zsh

set -e

LOGGING_ENABLED=1
LOG_LEVEL="INFO"
LOG_INFO="INFO"
LOG_DEBUG="DEBUG"
LOG_WARN="WARN"
LOG_ERROR="ERROR"

TIMESTAMP_FORMAT="date +%d-%m-%YT%H:%M:%S"

PROJECT_ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "${PROJECT_ROOT_DIR}"

DEPENDENCIES_ROOT_DIR=${1:-"${PROJECT_ROOT_DIR}/Pods"}

BASE_DIR="$(pwd)"

TMP_DIR_NAME="xcframework-tmp"
DEVICE_COMMAND_MARKER="IPHONEOS"
LOAD_SIMULATOR_CODE="7"

ARCH_ARM64="arm64"
ARCH_X86_64="x86_64"
SIM_TARGET_MARKER="-sim"

function log() {
  local MESSAGE=${1}
  local LEVEL=${2:-"${LOG_DEBUG}"}

  if [ ${LOGGING_ENABLED} -ne 1 ]; then
    return
  fi

  echo "[$(eval ${TIMESTAMP_FORMAT})][${LEVEL}] ${MESSAGE}"
}

function info() {
  log ${1} ${LOG_INFO}
}

function warn() {
  log ${1} ${LOG_WARN}
}

function error() {
  log ${1} ${LOG_ERROR}
}

function get_arm64_min_ios_version() {
  local OBJECT_FILE=${1}
  local MIN_IOS_VERSION="$(xcrun vtool -show -arch arm64 ${OBJECT_FILE} | grep -oE -A3 'LC_VERSION_MIN_IPHONEOS|LC_BUILD_VERSION' | grep -oE 'version.*' | sed -E 's/version[[:space:]]*//')"
  echo ${MIN_IOS_VERSION}
}

function get_arm64_sdk_version() {
  local OBJECT_FILE=${1}
  local SDK_VERSION="$(xcrun vtool -show -arch arm64 ${OBJECT_FILE} | grep -oE -A3 'LC_VERSION_MIN_IPHONEOS|LC_BUILD_VERSION' | grep -oE 'sdk.*' | sed -E 's/sdk[[:space:]]*//')"
  echo ${SDK_VERSION}
}

function patch_object_to_arm64_sim() {
  local OBJECT_FILE=${1}

  if ! which arm64-to-sim >/dev/null 2>&1; then
    log "Transmogrifier not installed. Getting it from sources..."

    git clone https://github.com/bogo/arm64-to-sim >/dev/null
    cd arm64-to-sim
    swift build -c release --arch arm64 --arch x86_64 >/dev/null
    cp .build/apple/Products/Release/arm64-to-sim /usr/local/bin
    cd ../

    log "Transmogrifier installation complete!"
  fi

  log "Patching object file ${OBJECT_FILE}"

  local OBJ_IOS_VERSION="$(get_arm64_min_ios_version ${OBJECT_FILE})"
  local OBJ_SDK_VERSION="$(get_arm64_sdk_version ${OBJECT_FILE})"
  arm64-to-sim ${OBJECT_FILE} ${OBJ_IOS_VERSION} ${OBJ_SDK_VERSION}
}

function patch_dynamic_binary_to_arm64_sim() {
  local INPUT_BIN=${1}
  local OUTPUT_BIN=${2}

  log "Patching dynamic ${ARCH_ARM64} simulator binary ${INPUT_BIN}"

  local BIN_IOS_VERSION="$(get_arm64_min_ios_version ${INPUT_BIN})"
  local BIN_SDK_VERSION="$(get_arm64_sdk_version ${INPUT_BIN})"
  xcrun vtool -arch "${ARCH_ARM64}" -set-build-version "${LOAD_SIMULATOR_CODE}" "${BIN_IOS_VERSION}" "${BIN_SDK_VERSION}" -replace -output "${OUTPUT_BIN}" "${INPUT_BIN}"

  log "Patching dynamic ${ARCH_ARM64} done. Result is saved at ${OUTPUT_BIN}"
}

function patch_static_binary_to_arm64_sim() {
  local INPUT_BIN=${1}
  local OUTPUT_BIN=${2}

  log "Patching static ${ARCH_ARM64} simulator binary ${INPUT_BIN}"

  rm -rf "./${INPUT_BIN}.objects"
  mkdir "${INPUT_BIN}.objects"
  cd "${INPUT_BIN}.objects"
  ar x "../${INPUT_BIN}" >/dev/null 2>&1
  rm -rf "../${INPUT_BIN}"
  for file in *.o; do patch_object_to_arm64_sim $file; done;
  ar crv "../${OUTPUT_BIN}" *.o >/dev/null 2>&1
  cd ../
  rm -rf "./${INPUT_BIN}.objects"

  log "Patching static ${ARCH_ARM64} done. Result is saved at ${OUTPUT_BIN}"
}

function patch_binary_to_arm64_sim() {
  local INPUT_BIN=${1}
  local OUTPUT_BIN=${2}

  log "Patching binary ${INPUT_BIN} for ${ARCH_ARM64} simulator"

  if xcrun vtool -show -arch "${ARCH_ARM64}" "${INPUT_BIN}" 2>/dev/null | grep "${DEVICE_COMMAND_MARKER}" >/dev/null 2>&1; then
    log "Dynamic binary found"
    patch_dynamic_binary_to_arm64_sim "${INPUT_BIN}" "${OUTPUT_BIN}"
  else
    log "Static binary found"
    patch_static_binary_to_arm64_sim "${INPUT_BIN}" "${OUTPUT_BIN}"
  fi
}

function extract_device_binary() {
  local INPUT_BIN=${1}
  local REQUIRED_ARCH=${2}
  local OUTPUT_BIN="${INPUT_BIN}.${REQUIRED_ARCH}"

  log "Extracting device binary from ${INPUT_BIN} to ${OUTPUT_BIN}"

  if ! lipo -info "${INPUT_BIN}" | grep -E "\s+${REQUIRED_ARCH}(\s+|$)" >/dev/null 2>&1; then
    warn "Device arch "${REQUIRED_ARCH}" not found in binary"
    return
  fi

  if ! lipo -info "${INPUT_BIN}" | grep -E "Non-fat" >/dev/null 2>&1; then
    log "Thining ${REQUIRED_ARCH} from ${INPUT_BIN} to ${OUTPUT_BIN}"
    lipo -thin "${REQUIRED_ARCH}" "${INPUT_BIN}" -output "${OUTPUT_BIN}"
  else
    mv "${INPUT_BIN}" "${OUTPUT_BIN}"
  fi

  log "Device binary for ${REQUIRED_ARCH} extracted - ${OUTPUT_BIN}!"
}

function extract_sim_binary() {
  local INPUT_BIN=${1}
  local REQUIRED_ARCH=${2}
  local OUTPUT_BIN="${INPUT_BIN}.${REQUIRED_ARCH}${SIM_TARGET_MARKER}"

  log "Extracting simulator binary from ${INPUT_BIN} to ${OUTPUT_BIN}"

  if ! lipo -info "${INPUT_BIN}" | grep -E "\s+${REQUIRED_ARCH}(\s+|$)" >/dev/null 2>&1; then
    warn "Simulator arch ${REQUIRED_ARCH} not found in binary ${INPUT_BIN}"
    return
  fi

  if ! lipo -info "${INPUT_BIN}" | grep -E "Non-fat" >/dev/null 2>&1; then
    log "Thining ${REQUIRED_ARCH} from ${INPUT_BIN} to ${OUTPUT_BIN}"
    lipo -thin "${REQUIRED_ARCH}" "${INPUT_BIN}" -output "${OUTPUT_BIN}"
  else
    mv "${INPUT_BIN}" "${OUTPUT_BIN}"
  fi

  if [[ "${REQUIRED_ARCH}" == "${ARCH_ARM64}" ]]; then
    log "Patching is required for arm64 simulator"
    patch_binary_to_arm64_sim "${OUTPUT_BIN}" "${OUTPUT_BIN}"
  fi

  log "Simulator binary for ${REQUIRED_ARCH} extracted - ${OUTPUT_BIN}!"
}

function generate_universal_binary() {
  local INPUT_BINARIES_LIST=("$@")
  local BINARIES_COUNT=$#

  if [ ${BINARIES_COUNT} -eq 0 ]; then
    warn "Provided list is empty"
    return
  fi

  local EXISTING_BINARIES_SEQUENCE=""
  local OUTPUT_BINARY="${INPUT_BINARIES_LIST[${BINARIES_COUNT}]}"
  unset 'INPUT_BINARIES_LIST[-1]'

  log "Generating universal binary ${OUTPUT_BINARY} for provided binaries: ${INPUT_BINARIES_LIST}"

  local EXISTING_BINARIES_COUNT=0
  for (( i=1; i<BINARIES_COUNT; i++ )); do
    local BINARY="${INPUT_BINARIES_LIST[$i]}"
    if test -f "${BINARY}"; then
      EXISTING_BINARIES_SEQUENCE+="${BINARY} "
      EXISTING_BINARIES_COUNT=$((EXISTING_BINARIES_COUNT+1))
    fi
  done

  if [ ${EXISTING_BINARIES_COUNT} -eq 0 ]; then
    warn "No existing binaries found"
    return
  fi

  if [ ${EXISTING_BINARIES_COUNT} -eq 1 ]; then
    log "The only framework is found: ${EXISTING_BINARIES_SEQUENCE} => No-fat result binary ${OUTPUT_BINARY} is generated"
    eval "mv ${EXISTING_BINARIES_SEQUENCE} ${OUTPUT_BINARY}"
    return
  fi

  log "The following binaries are found: ${EXISTING_BINARIES_SEQUENCE} - generating universal binary..."

  eval "lipo -create ${EXISTING_BINARIES_SEQUENCE} -output ${OUTPUT_BINARY}"

  log "Universal binary is built. Result saved at ${OUTPUT_BINARY}"
}

function create_patched_framework_with_binary() {
  local REF_FRAMEWORK_NAME=${1}
  local NEW_BINARY=${2}
  local OUTPUT_FRAMEWORK_DIR=${3}

  log "Creating patched framework based on ${REF_FRAMEWORK_NAME}.framework with ${NEW_BINARY} binary"

  if ! test -d "${REF_FRAMEWORK_NAME}.framework"; then
    warn "Reference framework is not found"
    return
  fi

  if ! test -f "${NEW_BINARY}"; then
    warn "New binary is not found"
    return
  fi

  cp -a "${REF_FRAMEWORK_NAME}.framework" "${OUTPUT_FRAMEWORK_DIR}/${REF_FRAMEWORK_NAME}.framework"
  cp "${NEW_BINARY}" "${OUTPUT_FRAMEWORK_DIR}/${REF_FRAMEWORK_NAME}.framework/${REF_FRAMEWORK_NAME}"

  log "Patched framework is generated and saved at ${OUTPUT_FRAMEWORK_DIR}/${REF_FRAMEWORK_NAME}.framework"
}

function generate_xcframework_from_frameworks() {
  local INPUT_FRAMEWORKS_LIST=("$@")
  local FRAMEWORKS_COUNT=$#

  if [ ${FRAMEWORKS_COUNT} -eq 0 ]; then
    warn "Provided list is empty"
    return
  fi

  declare -a EXISTING_FRAMEWORKS
  EXISTING_FRAMEWORKS=()

  local OUTPUT_XCFRAMEWORK="${INPUT_FRAMEWORKS_LIST[${FRAMEWORKS_COUNT}]}"
  unset 'INPUT_FRAMEWORKS_LIST[-1]'

  log "Generating XCFramework ${OUTPUT_XCFRAMEWORK} for frameworks: ${INPUT_FRAMEWORKS_LIST}"

  local EXISTING_FRAMEWORKS_COUNT=0
  for (( i=1; i<FRAMEWORKS_COUNT; i++ )); do
    local CUR_FRAMEWORK="${INPUT_FRAMEWORKS_LIST[$i]}"
    if test -d "${CUR_FRAMEWORK}"; then
      EXISTING_FRAMEWORKS+=("${CUR_FRAMEWORK}")
      EXISTING_FRAMEWORKS_COUNT=$((EXISTING_FRAMEWORKS_COUNT+1))
    fi
  done

  if [ ${EXISTING_FRAMEWORKS_COUNT} -eq 0 ]; then
    warn "No frameworks found for generation"
    return
  fi

  local XCFRAMEWORK_GENERATE_COMMAND="xcodebuild -create-xcframework -output "${OUTPUT_XCFRAMEWORK}""
  for (( i=1; i<=${EXISTING_FRAMEWORKS_COUNT}; i++ )); do
    XCFRAMEWORK_GENERATE_COMMAND+=" -framework "${EXISTING_FRAMEWORKS[$i]}""
  done

  log "Generation ${OUTPUT_XCFRAMEWORK} XCFramework for found ${EXISTING_FRAMEWORKS_COUNT} frameworks"

  if eval ${XCFRAMEWORK_GENERATE_COMMAND} 2>&1 | grep -E "error"; then
    error "Failed to generate ${OUTPUT_XCFRAMEWORK} with command '${XCFRAMEWORK_GENERATE_COMMAND}'"
    exit 1
  fi

  log "XCFramework is successfully generated - ${OUTPUT_XCFRAMEWORK}"
}

function generate_xcframework_from_static_libs() {
  local INPUT_STATIC_LIBS_LIST=("$@")
  local STATIC_LIBS_COUNT=$#

  if [ ${STATIC_LIBS_COUNT} -eq 0 ]; then
    warn "Provided list is empty"
    return
  fi

  declare -a EXISTING_STATIC_LIBS
  EXISTING_STATIC_LIBS=()

  local OUTPUT_XCFRAMEWORK="${INPUT_STATIC_LIBS_LIST[${STATIC_LIBS_COUNT}]}"
  unset 'INPUT_STATIC_LIBS_LIST[-1]'

  log "Generating XCFramework ${OUTPUT_XCFRAMEWORK} for static libs: ${INPUT_STATIC_LIBS_LIST}"

  local EXISTING_STATIC_LIBS_COUNT=0
  for (( i=1; i<STATIC_LIBS_COUNT; i++ )); do
    local CUR_STATIC_LIB="${INPUT_STATIC_LIBS_LIST[$i]}"
    if [[ "${CUR_STATIC_LIB}" == "headers" ]]; then
      break
    fi
    if test -f "${CUR_STATIC_LIB}"; then
      EXISTING_STATIC_LIBS+=("${CUR_STATIC_LIB}")
      EXISTING_STATIC_LIBS_COUNT=$((EXISTING_STATIC_LIBS_COUNT+1))
    fi
  done

  if [ ${EXISTING_STATIC_LIBS_COUNT} -eq 0 ]; then
    warn "No static libs found for generation"
    return
  fi

  declare -a EXISTING_STATIC_LIBS_HEADERS_DIRS
  EXISTING_STATIC_LIBS_HEADERS_DIRS=()
  local EXISTING_STATIC_LIBS_HEADERS_DIRS_COUNT=0
  for (( i=EXISTING_STATIC_LIBS_COUNT+1; i<STATIC_LIBS_COUNT; i++ )); do
    local CUR_STATIC_LIB_HEADER_DIR="${INPUT_STATIC_LIBS_LIST[$i]}"
    if test -d "${CUR_STATIC_LIB_HEADER_DIR}"; then
      EXISTING_STATIC_LIBS_HEADERS_DIRS+=("${CUR_STATIC_LIB_HEADER_DIR}")
      EXISTING_STATIC_LIBS_HEADERS_DIRS_COUNT=$((EXISTING_STATIC_LIBS_HEADERS_DIRS_COUNT+1))
    fi
  done

  local XCFRAMEWORK_GENERATE_COMMAND="xcodebuild -create-xcframework -output "${OUTPUT_XCFRAMEWORK}""
  for (( i=1; i<=${EXISTING_STATIC_LIBS_COUNT}; i++ )); do
    XCFRAMEWORK_GENERATE_COMMAND+=" -library "${EXISTING_STATIC_LIBS[$i]}""
    for (( j=1; j<=${EXISTING_STATIC_LIBS_HEADERS_DIRS_COUNT}; j++ )); do
      XCFRAMEWORK_GENERATE_COMMAND+=" -headers "${EXISTING_STATIC_LIBS_HEADERS_DIRS[$j]}""
    done
  done

  log "Generation ${OUTPUT_XCFRAMEWORK} XCFramework for found ${EXISTING_STATIC_LIBS_COUNT} static libs"

  if eval ${XCFRAMEWORK_GENERATE_COMMAND} 2>&1 | grep -E "error"; then
    error "Failed to generate ${OUTPUT_XCFRAMEWORK} with command '${XCFRAMEWORK_GENERATE_COMMAND}'"
    exit 1
  fi

  log "XCFramework is successfully generated - ${OUTPUT_XCFRAMEWORK}"
}

info "Patching frameworks at ${DEPENDENCIES_ROOT_DIR} started"

for FRAMEWORK in $(find "${DEPENDENCIES_ROOT_DIR}" -name "*.framework" | grep -vE ".xcframework"); do
  local LIB_NAME=$(basename ${FRAMEWORK} | cut -d. -f1)
  local FRAMEWORK_DIR=$(dirname "${FRAMEWORK}")

  if test -d "${FRAMEWORK_DIR}/${LIB_NAME}.xcframework"; then
    info "Using existing XCFramework ${FRAMEWORK_DIR}/${LIB_NAME}.xcframework"
    continue
  fi

  info "Patching ${FRAMEWORK}..."

  cd "${BASE_DIR}/${FRAMEWORK_DIR}"
  rm -rf "./${FRAMEWORK}/Modules/${LIB_NAME}.swiftmodule"
  rm -rf "./${TMP_DIR_NAME}"
  mkdir "./${TMP_DIR_NAME}"
  cd "${TMP_DIR_NAME}"

  cp -a "../${LIB_NAME}.framework" "${LIB_NAME}.framework"

  # cp + rm instead of mv due to possible symlinks existence
  cp "${LIB_NAME}.framework/${LIB_NAME}" "${LIB_NAME}"
  rm "${LIB_NAME}.framework/${LIB_NAME}"

  extract_device_binary "${LIB_NAME}" "${ARCH_ARM64}"
  extract_sim_binary "${LIB_NAME}" "${ARCH_ARM64}"
  extract_sim_binary "${LIB_NAME}" "${ARCH_X86_64}"
  generate_universal_binary "${LIB_NAME}.${ARCH_X86_64}${SIM_TARGET_MARKER}" "${LIB_NAME}.${ARCH_ARM64}${SIM_TARGET_MARKER}" "${LIB_NAME}${SIM_TARGET_MARKER}"

  mkdir "${ARCH_ARM64}"
  create_patched_framework_with_binary "${LIB_NAME}" "${LIB_NAME}.${ARCH_ARM64}" "${ARCH_ARM64}"

  OUTPUT_SIM_FRAMEWORK_DIR="patched${SIM_TARGET_MARKER}"
  mkdir "${OUTPUT_SIM_FRAMEWORK_DIR}"
  create_patched_framework_with_binary "${LIB_NAME}" "${LIB_NAME}${SIM_TARGET_MARKER}" "${OUTPUT_SIM_FRAMEWORK_DIR}"

  generate_xcframework_from_frameworks "${ARCH_ARM64}/${LIB_NAME}.framework" "${OUTPUT_SIM_FRAMEWORK_DIR}/${LIB_NAME}.framework" "${LIB_NAME}.xcframework"

  rm -rf "./${SIM_TARGET_MARKER}"
  rm -rf "./${ARCH_ARM64}"

  cd ../

  if test -d "${TMP_DIR_NAME}/${LIB_NAME}.xcframework"; then
    mv "${TMP_DIR_NAME}/${LIB_NAME}.xcframework" .
    info "Generated ${FRAMEWORK_DIR}/${LIB_NAME}.xcframework based on ${FRAMEWORK}"
  fi

  rm -rf "./${TMP_DIR_NAME}"
done

info "Patching frameworks done!"

cd "${BASE_DIR}"

info "Patching static libs at ${DEPENDENCIES_ROOT_DIR} started"

for STATIC_LIB in $(find "${DEPENDENCIES_ROOT_DIR}" -name "*.a" | grep -vE "(.xcframework)"); do
  local LIB_NAME=$(basename ${STATIC_LIB} | cut -d. -f1)
  local STATIC_LIB_DIR=$(dirname "${STATIC_LIB}")

  if test -d "${STATIC_LIB_DIR}/${LIB_NAME}.xcframework"; then
    info "Using existing XCFramework ${STATIC_LIB_DIR}/${LIB_NAME}.xcframework"
    continue
  fi

  info "Patching ${STATIC_LIB}..."

  cd "${BASE_DIR}/${STATIC_LIB_DIR}"
  rm -rf "./${TMP_DIR_NAME}"
  mkdir "./${TMP_DIR_NAME}"
  cd "${TMP_DIR_NAME}"

  cp -a "../${LIB_NAME}.a" "${LIB_NAME}"

  extract_device_binary "${LIB_NAME}" "${ARCH_ARM64}"
  extract_sim_binary "${LIB_NAME}" "${ARCH_ARM64}"
  extract_sim_binary "${LIB_NAME}" "${ARCH_X86_64}"
  generate_universal_binary "${LIB_NAME}.${ARCH_X86_64}${SIM_TARGET_MARKER}" "${LIB_NAME}.${ARCH_ARM64}${SIM_TARGET_MARKER}" "${LIB_NAME}${SIM_TARGET_MARKER}"

  mkdir "${ARCH_ARM64}"
  cp "${LIB_NAME}.${ARCH_ARM64}" "${ARCH_ARM64}/${LIB_NAME}.a"

  OUTPUT_SIM_STATIC_LIB_DIR="patched${SIM_TARGET_MARKER}"
  mkdir "${OUTPUT_SIM_STATIC_LIB_DIR}"
  cp "${LIB_NAME}${SIM_TARGET_MARKER}" "${OUTPUT_SIM_STATIC_LIB_DIR}/${LIB_NAME}.a"

  # .a file should be in /lib folder
  # headers should be in /headers or /include folder
  # not so reliable - better provide headers dirs explicitly in other script
  STATIC_LIB_ROOT_DIR=$(dirname ${STATIC_LIB_DIR})
  HEADERS_DIR="${BASE_DIR}/${STATIC_LIB_ROOT_DIR}/headers"
  INCLUDE_DIR="${BASE_DIR}/${STATIC_LIB_ROOT_DIR}/include"
  generate_xcframework_from_static_libs "${ARCH_ARM64}/${LIB_NAME}.a" "${OUTPUT_SIM_STATIC_LIB_DIR}/${LIB_NAME}.a" "headers" ${HEADERS_DIR} ${INCLUDE_DIR} "${LIB_NAME}.xcframework"

  rm -rf "./${SIM_TARGET_MARKER}"
  rm -rf "./${ARCH_ARM64}"

  cd ../

  if test -d "${TMP_DIR_NAME}/${LIB_NAME}.xcframework"; then
    mv "${TMP_DIR_NAME}/${LIB_NAME}.xcframework" .
  fi

  rm -rf "./${TMP_DIR_NAME}"

  cd "${BASE_DIR}/${STATIC_LIB_ROOT_DIR}"

  if test -d "lib/${LIB_NAME}.xcframework"; then
    mv "lib/${LIB_NAME}.xcframework" .
    info "Generated ${STATIC_LIB_DIR}/${LIB_NAME}.xcframework based on ${STATIC_LIB}"
  fi
done

info "Patching static libs done"
