# Kindle Fire HDX 7 (thor) → LineageOS 14.1 + Google Play

[Русская версия](README.ru.md)

A field log of moving a **Kindle Fire HDX 7, 3rd gen (2013, codename `thor`, model `KFTHWI`)**
from Fire OS 4.5.5.3 (Android 4.4) to **LineageOS 14.1 (Android 7.1.2)** with Google Play,
on Windows 11, without root. It contains our helper scripts and every pitfall we hit,
including one that is not documented elsewhere: **a primary GPT whose header points to empty sectors**,
which makes the old unlockable bootloader see no partitions at all.

> ⚠️ Use at your own risk. A mistake while writing the bootloader bricks the tablet.
> **thor (HDX 7) only.** apollo (HDX 8.9 2013) needs different files; saturn (HDX 8.9 2014) is not supported by this method.

## Result

| | Before | After |
|---|---|---|
| OS | Fire OS 4.5.5.3 (Android 4.4.3) | LineageOS 14.1-20220317 (Android 7.1.2) |
| Store | Amazon Appstore | Google Play (Open GApps pico 7.1) |
| Bootloader | locked | unlocked (aboot 3.2.3.2 + unlock code) |
| Recovery | stock | TWRP 3.1.1-0 |

## What you need

Third-party files are **not included** in this repository; download them yourself:

| File | Source | Check |
|---|---|---|
| Android Platform Tools (adb/fastboot) | `winget install Google.PlatformTools` | official Google package |
| `aboot-13-thor.zip`, `dd-0.5.zip`, `unlock.zip` | attachments of [XDA post #1006](https://xdaforums.com/showpost.php?p=75284993&postcount=1006) (login required) | aboot must be **13** (thor), not 14 |
| `thor-twrp-3.1.1-0.img` | [AFH, ggow/thor folder](https://androidfilehost.com/?w=files&flid=49739) | MD5 `6aae6362bedf1fb0741f9946ae3982ba` |
| `lineage-14.1-20220317-UNOFFICIAL-thor.zip` | Google Drive linked from the [LineageOS thread](https://xdaforums.com/t/rom-apollo-thor-lineage-14-1-17-mar-2022.4398657/) | `.md5sum` next to it |
| `open_gapps-arm-7.1-pico-*.zip` | [Open GApps on SourceForge](https://sourceforge.net/projects/opengapps/files/arm/) | `.md5` next to it |

At the time of writing, `thor-twrp-3.1.1-1` and `3.5.0_9.1` on AFH have **no mirrors** ("no mirrors found"), so 3.1.1-0 was used.

## Scripts in this repository

| File | Purpose |
|---|---|
| `scripts/write_aboot_twrp.bat` / `.ps1` | Replaces the manual `dd.exe` step in bulk mode. Finds the tablet among disks by exact size and partition layout, checks that recovery starts with `ANDROID!` and aboot is erased, writes in 512-byte blocks directly to the partition and verifies byte by byte. |
| `scripts/add_gpt_cmdline.py` | Appends ` gpt` to the kernel cmdline in a boot image header. Changes only the cmdline field. |
| `scripts/gpt_inspect.py` | Checks primary and backup GPT from dumps; detects the "header points to the wrong LBA" case. |

## Steps

### 1. Preparation
1. On the tablet: Settings → Device Options → tap the serial number 7 times → Developer Options → enable ADB.
2. Connect, allow debugging ("Always allow from this computer"). Back up personal files (`adb pull /sdcard/DCIM`, etc.).
3. Put `adb.exe`, `fastboot.exe`, `AdbWinApi.dll`, `AdbWinUsbApi.dll` into the `unlock` folder from `unlock.zip`, run `get_code.bat` → `unlock.code` (256 bytes) appears. `cuber` only computes the code from the eMMC ID.

### 2. Fastboot driver (important!)
`adb reboot bootloader` → the screen shows `[ fastboot ]`. Windows shows "Android" with error code 28.
Device Manager → "Android" → Update driver → Let me pick → "Universal Serial Bus devices" → **"ADB Device"** (Microsoft).
"WinUsb Device" does **not** work: fastboot cannot see it. The driver is lost every time the tablet was connected in a different mode; pick it again.

### 3. Bulk mode and writing the old aboot + TWRP
```
fastboot erase aboot
fastboot reboot
```
Recent fastboot no longer accepts `-i 0x1949`; it is not needed. The screen goes black, Windows sees "Qualcomm MMC Storage" and offers to format partitions: **always Cancel**.
Run `scripts/write_aboot_twrp.bat` (as administrator), confirm it found `Qualcomm MMC Storage`, type `YES` in capitals.

Pitfalls we hit:
* writing to `\\.\PhysicalDriveN` with a large block and WriteThrough fails with "Incorrect function"; writing to `\\.\HarddiskNPartitionM` in 512-byte blocks works;
* the `userdata` size from `/proc/partitions` is rounded to KiB (512 bytes smaller than the real one).

### 4. Unlock
Hold Power until it reboots → `[ fastboot ]` (the old aboot cannot boot the new boot image) →
```
fastboot flash unlock unlock.code
```
The tablet screen shows **`Unlock code is correct`**.

### 5. ⚠️ The main trap: the old aboot "sees" no partitions
Symptoms after unlocking:
* `fastboot flash boot ...` → `FAILED (remote: 'partition table doesn't exist')`;
* Power + Vol Up goes to fastboot instead of TWRP;
* `fastboot boot twrp.img` works, but the kernel logs `mmcblk0: unknown partition table`;
* `sgdisk` reports "Main partition table CRC mismatch", while the backup table is fine.

**Cause** (found with `gpt_inspect.py`): the GPT on this unit is non-standard: 24 entries, and **the primary header says
the entries are at LBA 28–33, but those sectors are zeros; the entries actually sit at LBA 2–7**. Amazon's newer aboot
tolerated this; the old 3.2.3.2 aboot reads from the LBA in the header and gets an empty table. A kernel without the
`gpt` parameter rejects the primary table; with `gpt` it falls back to the backup one.

**Working around it before the fix:** boot images from RAM with ` gpt` in the cmdline:
```
python scripts/add_gpt_cmdline.py thor-twrp-3.1.1-0.img twrp-gpt.img
fastboot boot twrp-gpt.img
```

**The fix** (in TWRP booted with `gpt`; first save `head.bin`/`tail.bin` dumps and check them with `gpt_inspect.py`):
```
adb shell
T=30777344   # number of mmcblk0 sectors (/proc/partitions × 2): check it for your tablet!
dd if=/dev/block/mmcblk0 of=/tmp/ent_src.bin bs=512 skip=2 count=6
dd if=/dev/block/mmcblk0 of=/tmp/ent_bak.bin bs=512 skip=$((T-7)) count=6
md5sum /tmp/ent_src.bin /tmp/ent_bak.bin          # must match
dd if=/tmp/ent_src.bin of=/dev/block/mmcblk0 bs=512 seek=28 count=6 conv=notrunc,fsync
sync
sgdisk --verify /dev/block/mmcblk0               # → No problems found
```
Only 6 empty reserved sectors are changed (before the first partition, which starts at LBA 131072);
the header and its CRC stay the same. After this the tablet boots on its own, and both `fastboot flash`
and entering TWRP with the buttons work.

### 6. Installing LineageOS and GApps without a touchscreen
In TWRP 3.1.1-0 the **touchscreen does not work** on this tablet, and the "Keep System Read only?" splash blocks `twrp` commands.
We ran the installers from the zips directly (extract them on the PC, since TWRP has no `unzip`):
```
adb shell twrp wipe data            # data (media is kept)
adb push lineage.zip /sdcard/ ; adb push gapps.zip /sdcard/
adb push lineage-update-binary /tmp/upd/lineage-ub      # META-INF/com/google/android/update-binary
adb shell "cd /tmp/upd && ./lineage-ub 3 1 /sdcard/lineage.zip"
adb push unzip /tmp/ubin/unzip                          # unzip-arm from the GApps zip
adb push gapps-update-binary /tmp/upd/gapps-ub
adb shell "cd /tmp/upd && PATH=/tmp/ubin:\$PATH ./gapps-ub 3 1 /sdcard/gapps.zip"
```
Check: `/system/priv-app` contains `Phonesky`, `PrebuiltGmsCore`, `GoogleServicesFramework`.

### 7. Speed tweaks (over adb)
```
settings put global window_animation_scale 0.25
settings put global transition_animation_scale 0.25
settings put global animator_duration_scale 0.25
settings put global wifi_scan_always_enabled 0
settings put global ble_scan_always_enabled 0
cmd package compile -m speed -a          # ~4 minutes
pm disable-user --user 0 <package>       # screensavers, egg, development, livepicker, ANT+, updater, weather
```
Language: Settings → Languages → Add a language → move it to the top (cannot be changed over adb without root).

## Don'ts
* Do not install Fire OS updates or stock Fire OS images: they lock the bootloader again.
* Do not format the drives Windows shows in bulk mode.
* Do not unplug the cable while writing.

## Links
* [Unlocking bootloader with any firmware (XDA)](https://xdaforums.com/t/thor-apollo-unlocking-bootloader-with-any-firmware.3463982/)
* [Step-by-step without root, post #1006](https://xdaforums.com/showpost.php?p=75284993&postcount=1006)
* [LineageOS 14.1 for apollo/thor](https://xdaforums.com/t/rom-apollo-thor-lineage-14-1-17-mar-2022.4398657/)
* [TWRP for thor/apollo](https://xdaforums.com/t/recovery-unlocked-bl-twrp-3-5-0_9-1.3322547/)
* [Connecting adb to Fire tablets (Amazon)](https://developer.amazon.com/docs/fire-tablets/connecting-adb-to-device.html)
