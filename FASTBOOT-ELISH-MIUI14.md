# elish MIUI 14 boot-only Fastboot 镜像打包

本仓库的 GitHub Actions 先构建内核与 AnyKernel3 中间产物；由于 Xiaomi Pad 5 Pro
（elish）没有可用 recovery，最终安装物由
`packaging/make_fastboot_images.sh` 转换为单独的 `boot_b` 镜像。

目标环境固定为：

- MIUI `V14.0.5.0.TKYCNXM`
- Android 13 / 安全补丁 `2023-09-01`
- 当前槽位 `b`
- Android boot image header v3
- 原厂 `vendor_boot_b`（包含原厂 DTB）
- 原厂 `dtbo_b`

脚本需要用户自己的原始 Magisk-patched `boot_b` 备份、Actions run `36678414768`
产出的内核 ZIP，以及 Magisk 29.0 的 x86-64 `magiskboot`。所有输入和输出
SHA-256 均已锁定。

```sh
./packaging/make_fastboot_images.sh \
  "boot_b-magisk-backup.img" \
  "APTKernel_MIUI_elish_ReSukiSU-SuSFS_anykernel3_61bd0b5e.zip" \
  "libmagiskboot.so" \
  "elish-fastboot-boot"
```

脚本会从 `boot_b` 的 Magisk 内置备份恢复原厂 ramdisk，生成 KernelSU-only 的
`boot_b-resukisu-susfs-qmpfix.img`。它不会读取、生成或修改 `vendor_boot`、DTB 或
DTBO，并会反向解包逐项验证结果，拒绝覆盖既有输出目录。

该内核修复了 elish 第二个 USB3 PHY 初始化时对 `USB3_DP_*` 寄存器的越界访问。
修复只改内核驱动，不需要自定义 DTB/DTBO。

刷写前必须在 bootloader fastboot 中确认 `unlocked: yes`、`current-slot: b` 和设备代号
`elish`。只允许执行：

```sh
fastboot.exe -s 686c19aa flash boot_b "boot_b-resukisu-susfs-qmpfix.img"
```

不要刷 `vendor_boot_b`、`dtbo_b`、A 槽或其他 ROM，不要修改 `vbmeta`，也不要执行
任何 Bootloader 锁定命令。
