# Checks the primary and backup GPT of a Fire HDX from two dumps taken in TWRP:
#   dd if=/dev/block/mmcblk0 of=/tmp/head.bin bs=512 count=34                  (LBA 0..33)
#   dd if=/dev/block/mmcblk0 of=/tmp/tail.bin bs=512 skip=$((TOTAL-33)) count=33 (last 33 LBAs)
# Entries are read from the LBA each header points to, which is exactly what the
# old aboot and the kernel do. Usage: python gpt_inspect.py head.bin tail.bin TOTAL_SECTORS
import struct, sys, zlib

head = open(sys.argv[1], 'rb').read()
tail = open(sys.argv[2], 'rb').read()
total = int(sys.argv[3])
tail_start = total - len(tail) // 512


def sector(lba):
    if lba * 512 + 512 <= len(head):
        return head[lba * 512:lba * 512 + 512]
    if lba >= tail_start:
        off = (lba - tail_start) * 512
        return tail[off:off + 512]
    raise ValueError(f'LBA {lba} is not in the dumps')


def check(label, lba):
    h = sector(lba)
    sig, rev, hsize, hcrc, _, cur, alt, first, last, guid, elba, n, esize, ecrc = struct.unpack('<8sIIIIQQQQ16sQIII', h[:92])
    hdr_ok = zlib.crc32(h[:16] + b'\0' * 4 + h[20:hsize]) & 0xffffffff == hcrc
    nsec = (n * esize + 511) // 512
    ents = b''.join(sector(elba + i) for i in range(nsec))[:n * esize]
    ent_ok = zlib.crc32(ents) & 0xffffffff == ecrc
    print(f'{label}: sig={sig} header_crc_ok={hdr_ok} entries_lba={elba} n={n} entries_crc_ok={ent_ok}')
    return ents if ent_ok else None, elba, n, esize


m = head[:512]
print('pMBR: signature', m[510:512].hex(), 'type', hex(m[450]), 'start', struct.unpack('<I', m[454:458])[0])
p_ents, p_lba, n, esize = check('primary', 1)
b_ents, _, _, _ = check('backup ', total - 1)

if p_ents is None and b_ents is not None:
    for lba in range(2, 34 - (n * esize + 511) // 512 + 1):
        cand = b''.join(sector(lba + i) for i in range((n * esize + 511) // 512))[:n * esize]
        if cand == b_ents:
            print(f'Valid entries found at LBA {lba}, but the primary header points to LBA {p_lba}.')
            print(f'Fix: copy LBA {lba}..{lba + (n * esize + 511) // 512 - 1} to LBA {p_lba} (see README).')
            break

for i in range(n):
    e = (p_ents or b_ents or b'')[i * esize:(i + 1) * esize]
    if len(e) < 128 or e[:16] == b'\0' * 16:
        continue
    first, last = struct.unpack('<QQ', e[32:48])
    print(f'  {i + 1:2} {e[56:128].decode("utf-16le").rstrip(chr(0)):14} {first:>9}..{last}')
