# Appends " gpt" to the kernel cmdline in an Android boot image (header v0) and nothing else.
# Needed on thor with the 3.2.3.2 aboot: it does not pass "gpt", so the kernel ignores the GPT.
import sys, zipfile

src, out = sys.argv[1], sys.argv[2]
data = zipfile.ZipFile(src).read('boot.img') if src.endswith('.zip') else open(src, 'rb').read()
assert data[:8] == b'ANDROID!', 'not an Android boot image'

CMD_OFF, CMD_LEN = 64, 512
cmd = data[CMD_OFF:CMD_OFF + CMD_LEN].split(b'\0')[0]
if b' gpt' not in b' ' + cmd:
    cmd += b' gpt'
assert len(cmd) < CMD_LEN
patched = data[:CMD_OFF] + cmd.ljust(CMD_LEN, b'\0') + data[CMD_OFF + CMD_LEN:]

changed = [i for i in range(len(data)) if data[i] != patched[i]]
assert len(patched) == len(data) and all(CMD_OFF <= i < CMD_OFF + CMD_LEN for i in changed)
open(out, 'wb').write(patched)
print(f'{out}: cmdline = {cmd.decode()} ({len(changed)} bytes changed, all inside the cmdline field)')
