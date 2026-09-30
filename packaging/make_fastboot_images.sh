#!/usr/bin/env bash

set -euo pipefail

readonly EXPECTED_BOOT_SHA256="e6db633967576c553709e1411a5b085aef463437ee671ead1fb6f61ddb75c38a"
readonly EXPECTED_VENDOR_BOOT_SHA256="03d3c0e7b4f7f38d29f6dd73d830ac44d012c5f88e42b1e751873fe91eadd54f"
readonly EXPECTED_KERNEL_ZIP_SHA256="b7bb4aa80c315b49f67e50c89ed411205868ebb2ea5d9bcdeb3f5007da13c9df"
readonly EXPECTED_MAGISKBOOT_SHA256="21be0ef297957c74184f0632dcf7d54777f064e64c8418c7d6ee107b9ddb3ffe"

readonly EXPECTED_IMAGE_SHA256="897904980b510fc12f28806854870f7a1819e271565d1cc8159a553cfe298445"
readonly EXPECTED_DTB_SHA256="b7544e02005afd8bf64fbece61201f987ccd8179645822436c3b4bbda29d4a9f"
readonly EXPECTED_DTBO_SHA256="5352e7d494195b1727369979ce4b18a8b49377853699c5d484fcf8cbabd889c0"

readonly EXPECTED_OUTPUT_BOOT_SHA256="7d9fef07f30f36c1e2f8f4302417abf824b726938576be77363ea27d6e951cd2"
readonly EXPECTED_OUTPUT_VENDOR_BOOT_SHA256="5ac1ee091069db50bd80f748c68802c16bf9634169042f2cabce9f3bd852d66a"
readonly EXPECTED_OUTPUT_DTBO_SHA256="5352e7d494195b1727369979ce4b18a8b49377853699c5d484fcf8cbabd889c0"

readonly BOOT_PARTITION_SIZE=201326592
readonly VENDOR_BOOT_PARTITION_SIZE=100663296
readonly DTBO_PARTITION_SIZE=33554432

usage() {
    cat <<'EOF'
用法：
  make_fastboot_images.sh <boot_b.img> <vendor_boot_b.img> <kernel.zip> <magiskboot> <output-dir>

输入必须精确对应：
  Xiaomi Pad 5 Pro (elish)
  MIUI V14.0.5.0.TKYCNXM / Android 13 / 2023-09
  GitHub Actions run 36651140648 / commit 05fc5af1

脚本不会修改输入文件，不会覆盖既有输出目录，也不会清理审计工作目录。
EOF
}

die() {
    printf '错误：%s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

sha256_of() {
    sha256sum "$1" | awk '{print $1}'
}

require_sha256() {
    local file="$1"
    local expected="$2"
    local actual

    actual="$(sha256_of "${file}")"
    [[ "${actual}" == "${expected}" ]] || die "SHA-256 不匹配：${file}，实际 ${actual}，预期 ${expected}"
}

require_size_at_most() {
    local file="$1"
    local maximum="$2"
    local actual

    actual="$(stat -c '%s' "${file}")"
    (( actual <= maximum )) || die "镜像超过分区容量：${file} 为 ${actual} 字节，分区上限 ${maximum} 字节"
}

[[ "$#" -eq 5 ]] || {
    usage >&2
    exit 2
}

for command_name in awk cmp grep install mkdir mktemp realpath sha256sum stat strings unzip; do
    require_command "${command_name}"
done

readonly BOOT_IMAGE="$(realpath "$1")"
readonly VENDOR_BOOT_IMAGE="$(realpath "$2")"
readonly KERNEL_ZIP="$(realpath "$3")"
readonly MAGISKBOOT="$(realpath "$4")"
readonly OUTPUT_DIR="$(realpath -m "$5")"

[[ -f "${BOOT_IMAGE}" ]] || die "boot 镜像不存在：${BOOT_IMAGE}"
[[ -f "${VENDOR_BOOT_IMAGE}" ]] || die "vendor_boot 镜像不存在：${VENDOR_BOOT_IMAGE}"
[[ -f "${KERNEL_ZIP}" ]] || die "内核 ZIP 不存在：${KERNEL_ZIP}"
[[ -x "${MAGISKBOOT}" ]] || die "magiskboot 不存在或不可执行：${MAGISKBOOT}"
[[ ! -e "${OUTPUT_DIR}" ]] || die "输出路径已存在，拒绝覆盖：${OUTPUT_DIR}"

require_sha256 "${BOOT_IMAGE}" "${EXPECTED_BOOT_SHA256}"
require_sha256 "${VENDOR_BOOT_IMAGE}" "${EXPECTED_VENDOR_BOOT_SHA256}"
require_sha256 "${KERNEL_ZIP}" "${EXPECTED_KERNEL_ZIP_SHA256}"
require_sha256 "${MAGISKBOOT}" "${EXPECTED_MAGISKBOOT_SHA256}"

readonly WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/elish-fastboot-images.XXXXXXXX")"
readonly BOOT_WORK="${WORK_DIR}/boot"
readonly VENDOR_BOOT_WORK="${WORK_DIR}/vendor_boot"
readonly STAGING_WORK="${WORK_DIR}/staging"
readonly VERIFY_BOOT_WORK="${WORK_DIR}/verify_boot"
readonly VERIFY_VENDOR_BOOT_WORK="${WORK_DIR}/verify_vendor_boot"

mkdir "${BOOT_WORK}" "${VENDOR_BOOT_WORK}" "${STAGING_WORK}" "${VERIFY_BOOT_WORK}" "${VERIFY_VENDOR_BOOT_WORK}"

unzip -p "${KERNEL_ZIP}" "kernels/miui/Image" >"${STAGING_WORK}/Image"
unzip -p "${KERNEL_ZIP}" "kernels/miui/dtb" >"${STAGING_WORK}/dtb"
unzip -p "${KERNEL_ZIP}" "kernels/miui/dtbo.img" >"${STAGING_WORK}/dtbo.img"

require_sha256 "${STAGING_WORK}/Image" "${EXPECTED_IMAGE_SHA256}"
require_sha256 "${STAGING_WORK}/dtb" "${EXPECTED_DTB_SHA256}"
require_sha256 "${STAGING_WORK}/dtbo.img" "${EXPECTED_DTBO_SHA256}"

(
    cd "${BOOT_WORK}"
    "${MAGISKBOOT}" unpack "${BOOT_IMAGE}"
)

if "${MAGISKBOOT}" cpio "${BOOT_WORK}/ramdisk.cpio" test; then
    ramdisk_test=0
else
    ramdisk_test=$?
fi
[[ "${ramdisk_test}" -eq 1 ]] || die "输入 boot ramdisk 不是预期的 Magisk-patched 状态（cpio test=${ramdisk_test}）"

"${MAGISKBOOT}" cpio "${BOOT_WORK}/ramdisk.cpio" restore

if "${MAGISKBOOT}" cpio "${BOOT_WORK}/ramdisk.cpio" test; then
    ramdisk_test=0
else
    ramdisk_test=$?
fi
[[ "${ramdisk_test}" -eq 0 ]] || die "Magisk 原厂 ramdisk 恢复失败（cpio test=${ramdisk_test}）"

install -m 0644 "${STAGING_WORK}/Image" "${BOOT_WORK}/kernel"

(
    cd "${VENDOR_BOOT_WORK}"
    "${MAGISKBOOT}" unpack "${VENDOR_BOOT_IMAGE}"
)
install -m 0644 "${STAGING_WORK}/dtb" "${VENDOR_BOOT_WORK}/dtb"

(
    cd "${BOOT_WORK}"
    "${MAGISKBOOT}" repack "${BOOT_IMAGE}" "${WORK_DIR}/boot_b-resukisu.img"
)
(
    cd "${VENDOR_BOOT_WORK}"
    "${MAGISKBOOT}" repack "${VENDOR_BOOT_IMAGE}" "${WORK_DIR}/vendor_boot_b-resukisu.img"
)
install -m 0644 "${STAGING_WORK}/dtbo.img" "${WORK_DIR}/dtbo_b-resukisu.img"

(
    cd "${VERIFY_BOOT_WORK}"
    "${MAGISKBOOT}" unpack "${WORK_DIR}/boot_b-resukisu.img"
)
if "${MAGISKBOOT}" cpio "${VERIFY_BOOT_WORK}/ramdisk.cpio" test; then
    ramdisk_test=0
else
    ramdisk_test=$?
fi
[[ "${ramdisk_test}" -eq 0 ]] || die "输出 boot 仍被检测为 Magisk-patched（cpio test=${ramdisk_test}）"
cmp "${VERIFY_BOOT_WORK}/kernel" "${STAGING_WORK}/Image"

(
    cd "${VERIFY_VENDOR_BOOT_WORK}"
    "${MAGISKBOOT}" unpack "${WORK_DIR}/vendor_boot_b-resukisu.img"
)
cmp "${VERIFY_VENDOR_BOOT_WORK}/dtb" "${STAGING_WORK}/dtb"
cmp "${VERIFY_VENDOR_BOOT_WORK}/ramdisk.cpio" "${VENDOR_BOOT_WORK}/ramdisk.cpio"
cmp "${WORK_DIR}/dtbo_b-resukisu.img" "${STAGING_WORK}/dtbo.img"

strings -a "${VERIFY_BOOT_WORK}/kernel" >"${WORK_DIR}/kernel.strings"
grep -Fq "Linux version 4.19.325-cip135-st19-aptusitu-perf+" "${WORK_DIR}/kernel.strings" || die "输出内核版本不匹配"
grep -Fq "KernelSU:" "${WORK_DIR}/kernel.strings" || die "输出内核未检测到 KernelSU"
grep -Fq "susfs_init" "${WORK_DIR}/kernel.strings" || die "输出内核未检测到 SUSFS"

require_size_at_most "${WORK_DIR}/boot_b-resukisu.img" "${BOOT_PARTITION_SIZE}"
require_size_at_most "${WORK_DIR}/vendor_boot_b-resukisu.img" "${VENDOR_BOOT_PARTITION_SIZE}"
require_size_at_most "${WORK_DIR}/dtbo_b-resukisu.img" "${DTBO_PARTITION_SIZE}"

require_sha256 "${WORK_DIR}/boot_b-resukisu.img" "${EXPECTED_OUTPUT_BOOT_SHA256}"
require_sha256 "${WORK_DIR}/vendor_boot_b-resukisu.img" "${EXPECTED_OUTPUT_VENDOR_BOOT_SHA256}"
require_sha256 "${WORK_DIR}/dtbo_b-resukisu.img" "${EXPECTED_OUTPUT_DTBO_SHA256}"

mkdir "${OUTPUT_DIR}"
install -m 0644 "${WORK_DIR}/boot_b-resukisu.img" "${OUTPUT_DIR}/boot_b-resukisu.img"
install -m 0644 "${WORK_DIR}/vendor_boot_b-resukisu.img" "${OUTPUT_DIR}/vendor_boot_b-resukisu.img"
install -m 0644 "${WORK_DIR}/dtbo_b-resukisu.img" "${OUTPUT_DIR}/dtbo_b-resukisu.img"

(
    cd "${OUTPUT_DIR}"
    sha256sum "boot_b-resukisu.img" "vendor_boot_b-resukisu.img" "dtbo_b-resukisu.img" >"SHA256SUMS"
)

cat >"${OUTPUT_DIR}/BUILD-METADATA.txt" <<EOF
device=elish
model=M2105K81AC
rom=V14.0.5.0.TKYCNXM
android=13
security_patch=2023-09-01
slot=b
kernel=4.19.325-cip135-st19-aptusitu-perf+
kernel_repository=AstideLabs/android_kernel_xiaomi_sm8250
kernel_commit=33d88af6404817e4df2343582bf6c1dd8ee10b89
packaging_repository=CwithW/android_kernel_xiaomi_sm8250
packaging_commit=05fc5af1e74e2350d821bfb5b9fc59c661ae62b7
github_actions_run=36651140648
root_solution=ReSukiSU-SuSFS
magisk_ramdisk=restored-to-stock
boot_template_sha256=${EXPECTED_BOOT_SHA256}
vendor_boot_template_sha256=${EXPECTED_VENDOR_BOOT_SHA256}
kernel_zip_sha256=${EXPECTED_KERNEL_ZIP_SHA256}
magiskboot_sha256=${EXPECTED_MAGISKBOOT_SHA256}
audit_work_directory=${WORK_DIR}
EOF

printf '构建和校验完成：%s\n' "${OUTPUT_DIR}"
printf 'Magisk 状态：已从 boot ramdisk 恢复为原厂状态；输出为 KernelSU-only。\n'
printf '审计工作目录（未自动删除）：%s\n' "${WORK_DIR}"
