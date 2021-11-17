#!/bin/bash
set -Eeuo pipefail

# sleep seconds between tests
SLEEP_SECS=5
# ioping count
IOPING_COUNT=50

# test target
TARGET_DIR="."
TARGET_FILE="${TARGET_DIR}/testfile"
TARGET_MOUNT_POINT="?" # will be set later

# UTC timestamp
CURRENT_TIMESTAMP="$(printf '%(%s)T\n' -1)"
# data root directory
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# report output directory
OUTPUT_DIR="${SCRIPT_DIR}/result/${CURRENT_TIMESTAMP}"

function SLEEP() {
    >&2 echo "[*] Sleeping..."
    sleep "${SLEEP_SECS}"
}

function collect_machine_info() {
    >&2 echo "[*] Collecting machine info..."

    TARGET_MOUNT_POINT="$(df ${TARGET_FILE} | tail -n 1 | rev | cut -d ' ' -f1 | rev)"

    # OS info
    cat > "${OUTPUT_DIR}/machine-info.env" <<EOF
HOSTNAME="$(cat /proc/sys/kernel/hostname)"
UNAME="$(uname -a)"
KERNEL="$(uname -r)"
KERNEL_CMDLINE=$(cat /proc/cmdline)
TIMESTAMP="${CURRENT_TIMESTAMP}"
FIO_VERSION="$(fio --version 2>&1)"
IOPING_VERSION="$(ioping --version 2>&1)"
DD_VERSION="$(dd --version 2>&1 | head -n 1)"
TARGET_MOUNT_POINT="${TARGET_MOUNT_POINT}"
ENTROPY_LEVEL="$(cat /proc/sys/kernel/random/entropy_avail)"
LOAD="$(cat /proc/loadavg)"
UPTIME="$(cat /proc/uptime)"

EOF

    if [ -f /etc/os-release ]; then
        cat /etc/os-release >> "${OUTPUT_DIR}/os.env"
    fi

    if command -v lsb_release >/dev/null 2>&1; then
        lsb_release -a >> "${OUTPUT_DIR}/lsb.env" || true
    fi

    cat /proc/cpuinfo > "${OUTPUT_DIR}/cpuinfo.log"
    cat /proc/meminfo > "${OUTPUT_DIR}/meminfo.log"

    if command -v lscpu >/dev/null 2>&1; then
        lscpu > "${OUTPUT_DIR}/lscpu.log"
    fi

    if command -v lspci >/dev/null 2>&1; then
        lspci > "${OUTPUT_DIR}/lspci.log"
    fi

    # disk info
    if command -v df >/dev/null 2>&1; then
        df -a > "${OUTPUT_DIR}/df.log"
    fi

    if command -v mount >/dev/null 2>&1; then
        mount > "${OUTPUT_DIR}/mount.log"
    fi

    if command -v findmnt >/dev/null 2>&1; then
        findmnt > "${OUTPUT_DIR}/findmnt.log"
    fi

    if command -v lsblk >/dev/null 2>&1; then
        lsblk --all --bytes --paths > "${OUTPUT_DIR}/lsblk.log" || true
    fi

    if command -v udevadm >/dev/null 2>&1; then
        udevadm info --export --name="${TARGET_MOUNT_POINT}" > "${OUTPUT_DIR}/udevadm.log" || true
    fi
}

# ioping - latency test
function do_ioping() {
    >&2 echo "[*] Latency test"
    ioping -c "${IOPING_COUNT}" "${TARGET_FILE}" | tee "${OUTPUT_DIR}/ioping.log" | tail -n 4
    sync
    SLEEP
}

# dd - for entertainment only
function do_dd() {
    # dd 64k
    >&2 echo "[*] dd small block zero"
    2>&1 dd if=/dev/zero of="${TARGET_FILE}" bs=64k count=16k conv=fdatasync | tee "${OUTPUT_DIR}/dd-zero-64k.log"
    sync
    SLEEP

    >&2 echo "[*] dd small block random"
    2>&1 dd if=/dev/urandom of="${TARGET_FILE}" bs=64k count=16k conv=fdatasync | tee -a "${OUTPUT_DIR}/dd-urandom-64k.log"
    sync
    SLEEP

    # dd 32M
    >&2 echo "[*] dd medium block zero"
    2>&1 dd if=/dev/zero of="${TARGET_FILE}" bs=32M count=32 oflag=direct | tee -a "${OUTPUT_DIR}/dd-zero-32m.log"
    sync
    SLEEP

    # note: /dev/urandom can only be read in 32M trunks
    >&2 echo "[*] dd medium block random"
    2>&1 dd if=/dev/urandom of="${TARGET_FILE}" bs=32M count=32 oflag=direct | tee -a "${OUTPUT_DIR}/dd-urandom-32m.log"
    sync
    SLEEP

    # dd 1G
    >&2 echo "[*] dd large block zero"
    2>&1 dd if=/dev/zero of="${TARGET_FILE}" bs=1G count=1 oflag=direct | tee -a "${OUTPUT_DIR}/dd-zero-1g.log"
    sync
    SLEEP
}

# run fio on all test cases
function do_fio() {
    for f in "${SCRIPT_DIR}/fio/"*.ini; do
        FIO_TEST_NAME="$(basename "${f}" .ini)"
        >&2 echo "[*] fio case ${FIO_TEST_NAME}"

        cat "${SCRIPT_DIR}/fio-global.ini" "$f" | fio --output-format "json,normal" --output "${OUTPUT_DIR}/fio-${FIO_TEST_NAME}.json" --filename "${TARGET_FILE}" - || >&2 echo "[-] fio failed"
        sync

        # print the human readable part of the result
        awk "/^}$/{y=1;next}y" "${OUTPUT_DIR}/fio-${FIO_TEST_NAME}.json"

        SLEEP
    done
}

>&2 echo "[*] Preparing report directory..."
mkdir -p "${OUTPUT_DIR}"
>&2 echo "[+] Report will be located at: ${OUTPUT_DIR}"

>&2 echo "[*] Pre-creating test file..."
fallocate --posix -l 4G "${TARGET_FILE}"
sync

collect_machine_info

>&2 echo "[+] Running tests on mount point: ${TARGET_MOUNT_POINT}"
ls -alh "${TARGET_FILE}"
SLEEP

do_ioping
do_dd
do_fio

>&2 echo "[*] Cleaning up"
rm -f "${TARGET_FILE}"

>&2 echo "[+] Done."
