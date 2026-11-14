# Arch Linux for iceland

为 **一加平板 3 Pro（OPD2513）** 与 **一加平板 4（OPD2514）** 构建 **Arch Linux ARM** 根文件系统与主线内核的 GitHub Actions 工程。设备代号 **iceland**，SoC 为 **SM8850（kaanapali）**。

流程沿用 [debian-sheng-kxt](https://github.com/rrrRex1336/debian-sheng-kxt) 的思路：Actions 里下载 Arch Linux ARM aarch64 根文件系统、编译主线内核、自动拉取设备固件，最后打包成可直接 `fastboot flash` 的镜像。

> **状态：构建流程已跑通，尚未在真机验证启动。**
> 已验证的组合（2026-11-14）：GNOME + `android_boot`、niri + `android_boot`、server + `uefi_esp`。
> 首次构建约 15 分钟，内核 ccache 命中后约 7 分钟。
> Debian 版本（[debian-iceland](https://github.com/rrrRex1336/debian-iceland)）同样已完整跑通构建。

## 产物

| 文件 | 说明 |
| --- | --- |
| `rootfs.img` | ext4 根文件系统，按 `PARTLABEL` 挂载根分区 |
| `boot.img` | Android boot header v2，含内核 `Image.gz`、DTB、initramfs |
| `esp.img` | FAT32 EFI 分区，含内核、DTB、initramfs、systemd-boot 与 `extlinux.conf` |
| `Image` / `Image.gz` / `initramfs.img` | 单独的内核与 initramfs |

`boot.img` 与 `esp.img` 二选一，由 `boot_method` 控制。

## 使用方法

1. Fork 本仓库。
2. **Actions → Build Arch Linux → Run workflow**，选择桌面、语言、分区等参数。
3. 构建完成后下载 artifacts。
4. 按下面的刷机步骤写入设备。

### 参数

| 参数 | 说明 | 默认 |
| --- | --- | --- |
| `desktop` | `GNOME` / `niri` / `server` | `GNOME` |
| `autologin` | 自动登录 | `true` |
| `username` | 用户名 | `user` |
| `hostname` | 主机名 | `iceland` |
| `language` | 系统语言 | `zh_CN.UTF-8` |
| `boot_mode` | 根分区：`dual (linux)` / `single (userdata)` / `custom` | `dual (linux)` |
| `custom_partition` | `boot_mode=custom` 时的分区名 | 空 |
| `boot_method` | `android_boot` / `uefi_esp` / `none` | `android_boot` |
| `quiet_boot` | 内核 cmdline 加 `quiet splash` | `true` |
| `kernel_repo` | 内核仓库 | `map220v/sm8850-mainline` |
| `kernel_branch` | 内核分支 | `iceland-7.3` |
| `kernel_config` | 内核配置路径 | `arch/arm64/configs/sm8850.config` |
| `kernel_fragment` | 追加配置片段 | `config/arch-iceland.fragment` |
| `dtb` | 打包的 DTB | `kaanapali-oneplus-iceland.dtb` |
| `firmware_repo` | 固件仓库（构建时自动下载） | `map220v/iceland-firmware` |
| `alarm_tarball` | Arch Linux ARM 根文件系统 tarball | `os.archlinuxarm.org` 最新 aarch64 |
| `image_size` | rootfs 镜像大小 | `12G` |

密码通过仓库 secret `ROOTFS_PASSWORD` 设置，未设置时默认 `archlinux`。

## 根文件系统

- 使用 [Arch Linux ARM](https://archlinuxarm.org) 官方 aarch64 tarball（约 800 MB）。
- 解包后 `pacman-key --init/--populate`，完整 `pacman -Syu`，再安装桌面与系统包。
- GNOME：`gnome` + `gdm`；niri：`niri` + `sddm`，附带 `foot`、`fuzzel`、`mako`、`swaybg`、`xwayland-satellite`。
- 内核不是 pacman 包，而是直接安装到 `/boot` 与 `/usr/lib/modules`，用 `mkinitcpio` 生成 initramfs（预设 `/etc/mkinitcpio.d/linux-iceland.preset`）。

## 内核

- 源码 [map220v/sm8850-mainline](https://github.com/map220v/sm8850-mainline)，分支 `iceland-7.3`（Linux 7.3）。
- 上游 `sm8850.config` 偏 Android，缺少 ext4、initramfs、cgroups、tmpfs 等，必须合并 [config/arch-iceland.fragment](config/arch-iceland.fragment) 才能引导 Arch。
- DTB：`arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts`（当前 `model = "OnePlus Pad 4"`，Pad 3 Pro 共用）。

## 固件

构建时自动 clone [map220v/iceland-firmware](https://github.com/map220v/iceland-firmware)，安装到 `/usr/lib/firmware`。同时安装 Arch 的 `linux-firmware` 以补齐通用固件。

## 刷机

> 会改分区，可能变砖。EDL 对 SM8850 基本不可用，fastboot 是底线。

双系统（保留 Android）：在 TWRP 里缩小 `userdata`，新建 `linux` 分区，然后：

```bash
fastboot erase dtbo_b
fastboot flash boot_b boot.img
fastboot flash linux rootfs.img
fastboot reboot
```

单系统：`boot_mode` 选 `single (userdata)`，改为 `fastboot flash userdata rootfs.img`。

## 启动方式与双系统切换

| 方式 | 说明 |
| --- | --- |
| `android_boot` | ABL 直接引导 Linux（boot header v2，DTB 在 header 内）。无启动菜单，切回 Android 要刷回原厂 boot 或换 slot。 |
| `uefi_esp` | 产出 `esp.img`，配合 **U-Boot** 使用，由 U-Boot 菜单选择 Android / Arch。需自行编译烧录 U-Boot 到 `boot_b`。 |

平板自带的 Qualcomm UEFI（`uefi_a/b`）只负责启动 ABL，不直接引导 Linux；要在开机时选系统，需要用 U-Boot（参考 [iceland-mainline](https://github.com/mzakamin-hub/iceland-mainline)）。`esp.img` 内已放好 systemd-boot、`loader/entries` 与 `extlinux/extlinux.conf`。

## 已知限制

- 未在 OPD2513 / OPD2514 真机验证。
- 音频、传感器、摄像头等设备包尚未处理。
- Deepin（DDE）在 Arch Linux ARM 上没有完整打包（缺 `startdde`、`dde-daemon` 等），因此桌面只提供 GNOME / niri。
- `uefi_esp` 需要你自备 U-Boot。
- 单系统模式会清空 Android 数据。

## 致谢

- [map220v](https://github.com/map220v) — sm8850 主线内核、iceland 固件
- [debian-sheng-kxt](https://github.com/rrrRex1336/debian-sheng-kxt) — 构建流程参考
- [iceland-mainline](https://github.com/mzakamin-hub/iceland-mainline) — U-Boot / 启动链资料
