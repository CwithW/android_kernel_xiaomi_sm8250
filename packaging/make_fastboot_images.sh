#!/usr/bin/env bash

set -euo pipefail

readonly EXPECTED_BOOT_SHA256="e6db633967576c553709e1411a5b085aef463437ee671ead1fb6f61ddb75c38a"
readonly EXPECTED_KERNEL_ZIP_SHA256="dae10e6bb1effbb6ba442a3be7e1664dd42dfe8d76cce18703600f560ac26dae"
readonly EXPECTED_MAGISKBOOT_SHA256="21be0ef297957c74184f0632dcf7d54777f064e64c8418c7d6ee107b9ddb3ffe"
readonly EXPECTED_IMAGE_SHA256="64cc9db521d2e61e85149b72e60b8563dfe9da74821df0f374b94066177e9aea"
readonly EXPECTED_OUTPUT_BOOT_SHA256="7f19b3c2cd4a2bda2ad83fc3f568eb31a5f5dc790da4ff9a0f1bf7c8039e8c58"

readonly EXPECTED_BUILD_COMMIT="61bd0b5e256485c8d42709bc93f5a450cf050923"
readonly EXPECTED_UPSTREAM_COMMIT="33d88af6404817e4df2343582bf6c1dd8ee10b89"
readonly GITHUB_ACTIONS_RUN="36678414768"
readonly BOOT_PARTITION_SIZE=201326592

usage() {
    cat <<'EOF'
用法：
  make_fastboot_images.sh <boot_b.img> <kernel.zip> <magiskboot> <output-dir>

输入必须精确对应：
  Xiaomi Pad 5 Pro (elish)
  MIUI V14.0.5.0.TKYCNXM / Android 13 / 2023-09
  GitHub Actions run 36678414768 / build commit 61bd0b5e

脚本只生成 boot_b 镜像。它不会读取、生成或修改 vendor_boot/DTB/DTBO，
也不会修改输入文件、覆盖既有输出目录或清理审计工作目录。
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

[[ "$#" -eq 4 ]] || {
    usage >&2
    exit 2
}

for command_name in awk cmp grep install mkdir mktemp realpath sha256sum stat strings unzip; do
    require_command "${command_name}"
done

readonly BOOT_IMAGE="$(realpath "$1")"
readonly KERNEL_ZIP="$(realpath "$2")"
readonly MAGISKBOOT="$(realpath "$3")"
readonly OUTPUT_DIR="$(realpath -m "$4")"

[[ -f "${BOOT_IMAGE}" ]] || die "boot 镜像不存在：${BOOT_IMAGE}"
[[ -f "${KERNEL_ZIP}" ]] || die "内核 ZIP 不存在：${KERNEL_ZIP}"
[[ -x "${MAGISKBOOT}" ]] || die "magiskboot 不存在或不可执行：${MAGISKBOOT}"
[[ ! -e "${OUTPUT_DIR}" ]] || die "输出路径已存在，拒绝覆盖：${OUTPUT_DIR}"

require_sha256 "${BOOT_IMAGE}" "${EXPECTED_BOOT_SHA256}"
require_sha256 "${KERNEL_ZIP}" "${EXPECTED_KERNEL_ZIP_SHA256}"
require_sha256 "${MAGISKBOOT}" "${EXPECTED_MAGISKBOOT_SHA256}"

readonly WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/elish-fastboot-boot.XXXXXXXX")"
readonly BOOT_WORK="${WORK_DIR}/boot"
readonly STAGING_WORK="${WORK_DIR}/staging"
readonly VERIFY_BOOT_WORK="${WORK_DIR}/verify_boot"
readonly OUTPUT_BOOT_NAME="boot_b-resukisu-susfs-qmpfix.img"

mkdir "${BOOT_WORK}" "${STAGING_WORK}" "${VERIFY_BOOT_WORK}"

unzip -p "${KERNEL_ZIP}" "kernels/miui/Image" >"${STAGING_WORK}/Image"
unzip -p "${KERNEL_ZIP}" "BUILD-METADATA.txt" >"${STAGING_WORK}/BUILD-METADATA.txt"

require_sha256 "${STAGING_WORK}/Image" "${EXPECTED_IMAGE_SHA256}"
grep -qx "build_commit=${EXPECTED_BUILD_COMMIT}" "${STAGING_WORK}/BUILD-METADATA.txt" \
    || die "Actions 产物的 build commit 不匹配"
grep -qx "upstream_kernel_commit=${EXPECTED_UPSTREAM_COMMIT}" "${STAGING_WORK}/BUILD-METADATA.txt" \
    || die "Actions 产物的 upstream commit 不匹配"
grep -qx 'target_device=elish' "${STAGING_WORK}/BUILD-METADATA.txt" \
    || die "Actions 产物的目标设备不是 elish"
grep -qx 'target_os=miui' "${STAGING_WORK}/BUILD-METADATA.txt" \
    || die "Actions 产物不是 MIUI 构建"
grep -qx 'kernelsu=1' "${STAGING_WORK}/BUILD-METADATA.txt" \
    || die "Actions 产物没有启用 KernelSU"

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
    cd "${BOOT_WORK}"
    "${MAGISKBOOT}" repack "${BOOT_IMAGE}" "${WORK_DIR}/${OUTPUT_BOOT_NAME}"
)

(
    cd "${VERIFY_BOOT_WORK}"
    "${MAGISKBOOT}" unpack "${WORK_DIR}/${OUTPUT_BOOT_NAME}"
)

if "${MAGISKBOOT}" cpio "${VERIFY_BOOT_WORK}/ramdisk.cpio" test; then
    ramdisk_test=0
else
    ramdisk_test=$?
fi
[[ "${ramdisk_test}" -eq 0 ]] || die "输出 boot 仍被检测为 Magisk-patched（cpio test=${ramdisk_test}）"
cmp "${VERIFY_BOOT_WORK}/kernel" "${STAGING_WORK}/Image"

strings -a "${VERIFY_BOOT_WORK}/kernel" >"${WORK_DIR}/kernel.strings"
grep -Fq "Linux version 4.19.325-cip135-st19-aptusitu-perf+" "${WORK_DIR}/kernel.strings" \
    || die "输出内核版本不匹配"
grep -Fq "KernelSU:" "${WORK_DIR}/kernel.strings" || die "输出内核未检测到 KernelSU"
grep -Fq "susfs_init" "${WORK_DIR}/kernel.strings" || die "输出内核未检测到 SUSFS"

require_size_at_most "${WORK_DIR}/${OUTPUT_BOOT_NAME}" "${BOOT_PARTITION_SIZE}"
if [[ -n "${EXPECTED_OUTPUT_BOOT_SHA256}" ]]; then
    require_sha256 "${WORK_DIR}/${OUTPUT_BOOT_NAME}" "${EXPECTED_OUTPUT_BOOT_SHA256}"
fi

mkdir "${OUTPUT_DIR}"
install -m 0644 "${WORK_DIR}/${OUTPUT_BOOT_NAME}" "${OUTPUT_DIR}/${OUTPUT_BOOT_NAME}"

(
    cd "${OUTPUT_DIR}"
    sha256sum "${OUTPUT_BOOT_NAME}" >"SHA256SUMS"
)

cat >"${OUTPUT_DIR}/BUILD-METADATA.txt" <<EOF
device=elish
model=M2105K81AC
rom=V14.0.5.0.TKYCNXM
android=13
security_patch=2023-09-01
slot=b
kernel=4.19.325-cip135-st19-aptusitu-perf+
kernel_repository=CwithW/android_kernel_xiaomi_sm8250
upstream_kernel_commit=${EXPECTED_UPSTREAM_COMMIT}
build_commit=${EXPECTED_BUILD_COMMIT}
github_actions_run=${GITHUB_ACTIONS_RUN}
root_solution=ReSukiSU-SuSFS
magisk_ramdisk=restored-to-stock
flash_partitions=boot_b
vendor_boot=stock-unmodified
dtb=stock-unmodified-inside-vendor_boot_b
dtbo=stock-unmodified
boot_template_sha256=${EXPECTED_BOOT_SHA256}
kernel_zip_sha256=${EXPECTED_KERNEL_ZIP_SHA256}
kernel_image_sha256=${EXPECTED_IMAGE_SHA256}
magiskboot_sha256=${EXPECTED_MAGISKBOOT_SHA256}
audit_work_directory=${WORK_DIR}
EOF

printf '构建和校验完成：%s\n' "${OUTPUT_DIR}"
printf '只允许刷写 boot_b；保持原厂 vendor_boot_b/DTB 和 dtbo_b。\n'
printf 'Magisk 状态：已从 boot ramdisk 恢复为原厂状态；输出为 KernelSU-only。\n'
printf '审计工作目录（未自动删除）：%s\n' "${WORK_DIR}"
