#!/bin/bash

set -euo pipefail

YELLOW='\033[1;33m'
RESET='\033[0m'

# 1. Check that podman is installed
if ! command -v podman >/dev/null 2>&1; then
  echo "Podman is not installed. Please install podman to proceed." >&2
  exit 1
fi

# 2. Attempt to locate matching USB serial device
MATCHING_SERIAL_DEVICE=""
DEVICE_WARNING=""

for dev in /dev/ttyUSB*; do
  [ -e "$dev" ] || continue

  sysdev=$(udevadm info -q path -n "$dev")
  sysattrs=$(udevadm info -a -p "$sysdev")

  if echo "$sysattrs" | grep -q 'ATTRS{idVendor}=="10c4"' && \
     echo "$sysattrs" | grep -q 'ATTRS{idProduct}=="ea60"'; then

    MATCHING_SERIAL_DEVICE="$dev"

    if [ "$(stat -c '%U' "$dev")" != "$USER" ]; then
      DEVICE_WARNING="Device ${dev} is not owned by user ${USER}; it may not be usable inside the container."
    fi

    break
  fi
done

if [ -z "$MATCHING_SERIAL_DEVICE" ]; then
  DEVICE_WARNING="No matching /dev/ttyUSB* device with VID:PID 10c4:ea60 found. The container will run without serial access."
fi

# 3. Compute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(realpath "$SCRIPT_DIR")"
MOUNT_PARENT="$(dirname "$PROJECT_DIR")"
CONTAINER_PARENT="/home/esp/$(basename "$MOUNT_PARENT")"

# 4. Show any warnings
if [ -n "$DEVICE_WARNING" ]; then
  echo -e "${YELLOW}${DEVICE_WARNING}${RESET}"
fi

# 5. Build podman args
PODMAN_ARGS=(
  --rm
  -v "${MOUNT_PARENT}:${CONTAINER_PARENT}:Z"
  -w "${CONTAINER_PARENT}/$(basename "$PROJECT_DIR")"
  --userns=keep-id
)

if [ -n "$MATCHING_SERIAL_DEVICE" ]; then
  PODMAN_ARGS+=(--device="${MATCHING_SERIAL_DEVICE}")
fi

# 6. Run with or without container command
if [ "$#" -eq 0 ]; then
  # Interactive shell
  exec podman run -it "${PODMAN_ARGS[@]}" docker.io/espressif/idf-rust:esp32_1.85.0.0
else
  # Pass arguments as command
  exec podman run "${PODMAN_ARGS[@]}" docker.io/espressif/idf-rust:esp32_1.85.0.0 "$@"
fi
