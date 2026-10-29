# Kindle Fire HDX 7 (thor) → LineageOS 14.1 + Google Play

[English version](README.md)

Журнал того, как планшет **Kindle Fire HDX 7, 3-е поколение (2013, кодовое имя `thor`, модель `KFTHWI`)**
перевели с Fire OS 4.5.5.3 (Android 4.4) на **LineageOS 14.1 (Android 7.1.2)** с Google Play,
на Windows 11, без root. Здесь лежат наши скрипты и все найденные подводные камни.

> ⚠️ Всё делается на свой риск. Ошибка при записи загрузчика превращает планшет в «кирпич».
> Только для **thor** (HDX 7). Для apollo (HDX 8.9 2013) нужны другие файлы, для saturn (HDX 8.9 2014) метод не работает.

## Итог

| | До | После |
|---|---|---|
| Система | Fire OS 4.5.5.3 (Android 4.4.3) | LineageOS 14.1-20220317 (Android 7.1.2) |
| Магазин | Amazon Appstore | Google Play (Open GApps pico 7.1) |
| Загрузчик | заблокирован | разблокирован (aboot 3.2.3.2 + unlock-код) |
| Recovery | стоковое | TWRP 3.1.1-0 |

## Что понадобится

Чужие файлы в репозиторий **не включены**, их надо скачать самому:

| Файл | Где брать | Проверка |
|---|---|---|
| Android Platform Tools (adb/fastboot) | `winget install Google.PlatformTools` | официальный пакет Google |
| `aboot-13-thor.zip`, `dd-0.5.zip`, `unlock.zip` | вложения [поста #1006 на XDA](https://xdaforums.com/showpost.php?p=75284993&postcount=1006) (нужен вход) | `aboot` должен быть **13** (thor), не 14 |
| `thor-twrp-3.1.1-0.img` | [AFH, папка ggow/thor](https://androidfilehost.com/?w=files&flid=49739) | MD5 `6aae6362bedf1fb0741f9946ae3982ba` |
| `lineage-14.1-20220317-UNOFFICIAL-thor.zip` | [Google Drive из темы LineageOS](https://xdaforums.com/t/rom-apollo-thor-lineage-14-1-17-mar-2022.4398657/) | `.md5sum` рядом |
| `open_gapps-arm-7.1-pico-*.zip` | [SourceForge Open GApps](https://sourceforge.net/projects/opengapps/files/arm/) | `.md5` рядом |

У `thor-twrp-3.1.1-1` и `3.5.0_9.1` на AFH сейчас **нет зеркал** («no mirrors found»), поэтому взяли 3.1.1-0.

## Скрипты в репозитории

| Файл | Зачем |
|---|---|
| `scripts/write_aboot_twrp.bat` / `.ps1` | Замена ручного `dd.exe` в bulk mode: сам находит планшет среди дисков по размеру и разметке, проверяет, что recovery начинается с `ANDROID!`, а aboot стёрт, пишет блоками по 512 байт прямо в раздел и сверяет побайтно. |
| `scripts/add_gpt_cmdline.py` | Добавляет ` gpt` в cmdline заголовка boot-образа. Меняет только поле cmdline. |
| `scripts/gpt_inspect.py` | Проверяет основную и резервную GPT по дампам; находит случай «заголовок указывает не туда». |

## Порядок действий

### 1. Подготовка
1. На планшете: «Настройки → Параметры устройства → 7 раз по серийному номеру → Параметры разработчика → Отладка ADB».
2. Подключить, разрешить отладку («Всегда разрешать с этого компьютера»). Скопировать личные файлы (`adb pull /sdcard/DCIM` и т.д.).
3. Положить в папку `unlock` из `unlock.zip` ещё `adb.exe`, `fastboot.exe`, `AdbWinApi.dll`, `AdbWinUsbApi.dll`, запустить `get_code.bat` → появится `unlock.code` (256 байт). `cuber` только вычисляет код по ID eMMC.

### 2. Драйвер fastboot (важно!)
`adb reboot bootloader` → на экране `[ fastboot ]`. Windows покажет «Android» с кодом 28.
Диспетчер устройств → «Android» → Обновить драйвер → Выбрать из списка → «Устройства USB» → **«Устройство ADB»** (Microsoft).
«WinUsb Device» **не подходит**: fastboot его не видит. Драйвер слетает каждый раз, когда планшет подключался в другом режиме, — выбирать заново.

### 3. Bulk mode и запись старого aboot + TWRP
```
fastboot erase aboot
fastboot reboot
```
Новый fastboot не понимает `-i 0x1949` — ключ не нужен. Экран чёрный, Windows видит «Qualcomm MMC Storage» и предлагает форматировать разделы — **всегда «Отмена»**.
Запустить `scripts/write_aboot_twrp.bat` (от администратора), проверить, что найден `Qualcomm MMC Storage`, ввести `YES` заглавными.

Подводные камни, на которые наступили:
* запись в `\\.\PhysicalDriveN` большим блоком с WriteThrough → «Неверная функция»; помогла запись в `\\.\HarddiskNPartitionM` блоками по 512 байт;
* размер `userdata` из `/proc/partitions` округлён до КБ (на 512 байт меньше реального).

### 4. Разблокировка
Удерживать питание до перезагрузки → `[ fastboot ]` (старый aboot не грузит новый boot) →
```
fastboot flash unlock unlock.code
```
На экране планшета: **`Unlock code is correct`**.

### 5. ⚠️ Главная ловушка: старый aboot «не видит» разделы
Симптомы после разблокировки:
* `fastboot flash boot ...` → `FAILED (remote: 'partition table doesn't exist')`;
* Power + Vol Up уходит в fastboot вместо TWRP;
* `fastboot boot twrp.img` работает, но ядро пишет `mmcblk0: unknown partition table`;
* `sgdisk` ругается «Main partition table CRC mismatch», а резервная таблица в порядке.

**Причина** (`gpt_inspect.py`): GPT на этом экземпляре нестандартная — 24 записи, и **заголовок основной таблицы
указывает, что записи лежат в LBA 28–33, а там нули; сами записи лежат в LBA 2–7**. Новый aboot Amazon это прощал,
старый 3.2.3.2 читает по адресу из заголовка и получает пустую таблицу. Ядро без параметра `gpt` основную таблицу
отвергает; с `gpt` берёт резервную.

**Как работать до исправления:** запускать образы из памяти с ` gpt` в cmdline:
```
python scripts/add_gpt_cmdline.py thor-twrp-3.1.1-0.img twrp-gpt.img
fastboot boot twrp-gpt.img
```

**Исправление** (в TWRP, запущенном с `gpt`; сначала сохранить дампы `head.bin`/`tail.bin` и проверить `gpt_inspect.py`):
```
adb shell
T=30777344   # число секторов mmcblk0 (из /proc/partitions × 2) — проверить для своего планшета!
dd if=/dev/block/mmcblk0 of=/tmp/ent_src.bin bs=512 skip=2 count=6
dd if=/dev/block/mmcblk0 of=/tmp/ent_bak.bin bs=512 skip=$((T-7)) count=6
md5sum /tmp/ent_src.bin /tmp/ent_bak.bin          # должны совпасть
dd if=/tmp/ent_src.bin of=/dev/block/mmcblk0 bs=512 seek=28 count=6 conv=notrunc,fsync
sync
sgdisk --verify /dev/block/mmcblk0               # → No problems found
```
Изменяются только 6 пустых служебных секторов (до первого раздела, который начинается с LBA 131072);
заголовок и его CRC не меняются. После этого планшет грузится сам, `fastboot flash` и вход в TWRP кнопками работают.

### 6. Установка LineageOS и GApps без сенсора
В TWRP 3.1.1-0 на этом планшете **не работает сенсор**, и заставка «Keep System Read only?» блокирует команды `twrp`.
Ставили напрямую через установщики из архивов (их достаём на ПК, т.к. в TWRP нет `unzip`):
```
adb shell twrp wipe data            # данные (media сохраняется)
adb push lineage.zip /sdcard/ ; adb push gapps.zip /sdcard/
adb push lineage-update-binary /tmp/upd/lineage-ub      # META-INF/com/google/android/update-binary
adb shell "cd /tmp/upd && ./lineage-ub 3 1 /sdcard/lineage.zip"
adb push unzip /tmp/ubin/unzip                          # unzip-arm из архива GApps
adb push gapps-update-binary /tmp/upd/gapps-ub
adb shell "cd /tmp/upd && PATH=/tmp/ubin:\$PATH ./gapps-ub 3 1 /sdcard/gapps.zip"
```
Проверка: в `/system/priv-app` есть `Phonesky`, `PrebuiltGmsCore`, `GoogleServicesFramework`.

### 7. Ускорение (через adb)
```
settings put global window_animation_scale 0.25
settings put global transition_animation_scale 0.25
settings put global animator_duration_scale 0.25
settings put global wifi_scan_always_enabled 0
settings put global ble_scan_always_enabled 0
cmd package compile -m speed -a          # ~4 минуты
pm disable-user --user 0 <пакет>         # заставки, egg, development, livepicker, ANT+, updater, погода
```
Язык: «Настройки → Языки → Добавить → Русский» и перетащить наверх (без root через adb не меняется).

## Чего не делать
* Не ставить обновления и стоковые прошивки Fire OS — снова заблокируют загрузчик.
* Не форматировать диски, которые Windows показывает в bulk mode.
* Не выключать кабель во время записи.

## Ссылки
* [Unlocking bootloader with any firmware (XDA)](https://xdaforums.com/t/thor-apollo-unlocking-bootloader-with-any-firmware.3463982/)
* [Пошаговая инструкция без root, пост #1006](https://xdaforums.com/showpost.php?p=75284993&postcount=1006)
* [LineageOS 14.1 для apollo/thor](https://xdaforums.com/t/rom-apollo-thor-lineage-14-1-17-mar-2022.4398657/)
* [TWRP для thor/apollo](https://xdaforums.com/t/recovery-unlocked-bl-twrp-3-5-0_9-1.3322547/)
* [Подключение adb к Fire (Amazon)](https://developer.amazon.com/docs/fire-tablets/connecting-adb-to-device.html)
