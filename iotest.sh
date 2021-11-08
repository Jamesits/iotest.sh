#!/bin/bash
set -Eeuo pipefail

SLEEP_SECS=5
IOPING_COUNT=50

TARGET_DIR="."
TARGET_FILE="${TARGET_DIR}/testfile"

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
OUTPUT_DIR="${SCRIPT_DIR}/result/$(printf '%(%s)T\n' -1)"

function SLEEP() {
    >&2 echo "[*] Sleeping..."
    sleep "${SLEEP_SECS}"
}

set +x

>&2 echo "[+] Preparing report directory..."
mkdir -p "${OUTPUT_DIR}"

>&2 echo "[+] Pre-creating test file..."
fallocate -l 4G "${TARGET_FILE}"
sync
ls -alh "${TARGET_FILE}"
SLEEP

# ioping
>&2 echo "[*] Latency test"
ioping -c "${IOPING_COUNT}" "${TARGET_FILE}" | tee "${OUTPUT_DIR}/ioping.log" | tail -n 4
sync
SLEEP

# dd 64k
>&2 echo "[*] dd small block zero"
2>&1 dd if=/dev/zero of="${TARGET_FILE}" bs=64k count=16k conv=fdatasync | tee "${OUTPUT_DIR}/dd-zero-small.log"
sync
SLEEP

>&2 echo "[*] dd small block random"
2>&1 dd if=/dev/urandom of="${TARGET_FILE}" bs=64k count=16k conv=fdatasync | tee -a "${OUTPUT_DIR}/dd-urandom-small.log"
sync
SLEEP

# dd 1G
>&2 echo "[*] dd large block zero"
2>&1 dd if=/dev/zero of="${TARGET_FILE}" bs=1G count=1 oflag=direct | tee -a "${OUTPUT_DIR}/dd-zero-large.log"
sync
SLEEP

>&2 echo "[*] dd large block random"
2>&1 dd if=/dev/urandom of="${TARGET_FILE}" bs=1G count=1 oflag=direct | tee -a "${OUTPUT_DIR}/dd-urandom-large.log"
sync
SLEEP

# fio
for f in "${SCRIPT_DIR}/fio/"*.ini; do
    >&2 echo "[*] fio case ${f}"

    cat "${SCRIPT_DIR}/fio-global.ini" "$f" | fio --output-format "json,normal" --output "${OUTPUT_DIR}/fio-$(basename "${f}").json" --filename "${TARGET_FILE}" -
    sync

    awk "/^}$/{y=1;next}y" "${OUTPUT_DIR}/fio-$(basename "${f}").json"

    SLEEP
done

>&2 echo "[+] Cleaning up"
rm -f "${TARGET_FILE}"

>&2 echo "[+] Done."
