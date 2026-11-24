import struct, lzma, io

def lz4_block(src, usize):
    out = bytearray(); i = 0; n = len(src)
    while i < n:
        t = src[i]; i += 1
        ll = t >> 4
        if ll == 15:
            while True:
                b = src[i]; i += 1; ll += b
                if b != 255: break
        out += src[i:i+ll]; i += ll
        if i >= n: break
        off = src[i] | (src[i+1] << 8); i += 2
        ml = t & 15
        if ml == 15:
            while True:
                b = src[i]; i += 1; ml += b
                if b != 255: break
        ml += 4
        st = len(out) - off
        if off >= ml: out += out[st:st+ml]
        else:
            for k in range(ml): out.append(out[st+k])
    return bytes(out)

def decomp(data, usize, comp):
    c = comp & 0x3f
    if c == 0: return data
    if c == 1:
        return lzma.LZMADecompressor(format=lzma.FORMAT_RAW, filters=[{"id": lzma.FILTER_LZMA1, "dict_size": 1<<24, "lc":3,"lp":0,"pb":2}]).decompress(data) if False else _lzma(data, usize)
    if c in (2, 3): return lz4_block(data, usize)
    raise ValueError(c)

def _lzma(data, usize):
    hdr = data[:5] + struct.pack('<Q', usize)
    d = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE)
    return d.decompress(hdr + data[5:])

def read_bundle(path):
    b = open(path, 'rb').read()
    p = 0
    def cstr():
        nonlocal p
        e = b.index(b'\0', p); s = b[p:e]; p = e + 1; return s
    cstr(); p += 4; cstr(); cstr()
    size, csz, usz, flags = struct.unpack('>qIII', b[p:p+20]); p += 20
    if flags & 0x80:
        raise NotImplementedError
    if flags & 0x200: p = (p + 15) & ~15
    info = decomp(b[p:p+csz], usz, flags); p += csz
    if flags & 0x200: p = (p + 15) & ~15
    q = 16
    nb = struct.unpack('>i', info[q:q+4])[0]; q += 4
    blocks = []
    for _ in range(nb):
        u, c, f = struct.unpack('>IIH', info[q:q+10]); q += 10; blocks.append((u, c, f))
    nn = struct.unpack('>i', info[q:q+4])[0]; q += 4
    nodes = []
    for _ in range(nn):
        off, sz, fl = struct.unpack('>qqI', info[q:q+20]); q += 20
        e = info.index(b'\0', q); nm = info[q:e].decode(); q = e + 1
        nodes.append((off, sz, fl, nm))
    data = bytearray()
    for u, c, f in blocks:
        data += decomp(b[p:p+c], u, f); p += c
    return {nm: bytes(data[off:off+sz]) for off, sz, fl, nm in nodes}

if __name__ == '__main__':
    import sys
    for f in sys.argv[1:]:
        r = read_bundle(f)
        print(f[-12:], {k: len(v) for k, v in r.items()})
