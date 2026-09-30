# elish MIUI 14 fastboot 镜像打包

本仓库的 GitHub Actions 先构建内核与 AnyKernel3 中间产物；由于 Xiaomi Pad 5 Pro
（elish）没有可用 recovery，最终安装物应由
`packaging/make_fastboot_images.sh` 转换为完整分区镜像。

目标环境固定为：

- MIUI `V14.0.5.0.TKYCNXM`
- Android 13 / 安全补丁 `2023-09-01`
- 当前槽位 `b`
- Android boot image header v3

脚本需要用户自己的 `boot_b`、`vendor_boot_b` 备份、Actions 产出的内核 ZIP 和
Magisk 29.0 的 x86-64 `magiskboot`。所有输入和预期输出 SHA-256 均已锁定。

```sh
./packaging/make_fastboot_images.sh \\
  "boot_b-current.img" \\
  "vendor_boot_b-current.img" \\
  "APTKernel_MIUI_elish_ReSukiSU-SuSFS_anykernel3_05fc5af1.zip" \\
  "libmagiskboot.so" \\
  "elish-fastboot-images"
```

脚本会从当前 `boot_b` 的 Magisk 内置备份恢复原厂 ramdisk，生成 KernelSU-only 的
`boot_b-resukisu.img`，并同时生成匹配的 `vendor_boot_b-resukisu.img` 和
`dtbo_b-resukisu.img`。它会反向解包并逐项验证结果，拒绝覆盖既有输出目录。

刷写前必须在 bootloader fastboot 中确认 `unlocked: yes`、`current-slot: b` 和设备代号
`elish`。不要刷入其他槽位或其他 ROM，也不要随意修改 `vbmeta`。
