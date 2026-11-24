import struct, io

COMMON = ("AABB\0AnimationClip\0AnimationCurve\0AnimationState\0Array\0Base\0BitField\0bitset\0bool\0char\0ColorRGBA\0Component\0data\0deque\0double\0dynamic_array\0FastPropertyName\0first\0float\0Font\0GameObject\0Generic Mono\0GradientNEW\0GUID\0GUIStyle\0int\0list\0long long\0map\0Matrix4x4f\0MdFour\0MonoBehaviour\0MonoScript\0m_ByteSize\0m_Curve\0m_EditorClassIdentifier\0m_EditorHideFlags\0m_Enabled\0m_ExtensionPtr\0m_GameObject\0m_Index\0m_IsArray\0m_IsStatic\0m_MetaFlag\0m_Name\0m_ObjectHideFlags\0m_PrefabInternal\0m_PrefabParentObject\0m_Script\0m_StaticEditorFlags\0m_Type\0m_Version\0Object\0pair\0PPtr<Component>\0PPtr<GameObject>\0PPtr<Material>\0PPtr<MonoBehaviour>\0PPtr<MonoScript>\0PPtr<Object>\0PPtr<Prefab>\0PPtr<Sprite>\0PPtr<TextAsset>\0PPtr<Texture>\0PPtr<Texture2D>\0PPtr<Transform>\0Prefab\0Quaternionf\0Rectf\0RectInt\0RectOffset\0second\0set\0short\0size\0SInt16\0SInt32\0SInt64\0SInt8\0staticvector\0string\0TextAsset\0TextMesh\0Texture\0Texture2D\0Transform\0TypelessData\0UInt16\0UInt32\0UInt64\0UInt8\0unsigned int\0unsigned long long\0unsigned short\0vector\0Vector2f\0Vector3f\0Vector4f\0m_ScriptingClassIdentifier\0Gradient\0Type*\0int2_storage\0int3_storage\0BoundsInt\0m_CorrespondingSourceObject\0m_PrefabInstance\0m_PrefabAsset\0FileSize\0Hash128\0").encode()

def cstr_at(buf, off):
    e = buf.index(b'\0', off); return buf[off:e].decode()

class R:
    def __init__(s, b, be=True): s.b = b; s.p = 0; s.be = be
    def u8(s): v = s.b[s.p]; s.p += 1; return v
    def i16(s): v = struct.unpack('>h' if s.be else '<h', s.b[s.p:s.p+2])[0]; s.p += 2; return v
    def u16(s): v = struct.unpack('>H' if s.be else '<H', s.b[s.p:s.p+2])[0]; s.p += 2; return v
    def i32(s): v = struct.unpack('>i' if s.be else '<i', s.b[s.p:s.p+4])[0]; s.p += 4; return v
    def u32(s): v = struct.unpack('>I' if s.be else '<I', s.b[s.p:s.p+4])[0]; s.p += 4; return v
    def i64(s): v = struct.unpack('>q' if s.be else '<q', s.b[s.p:s.p+8])[0]; s.p += 8; return v
    def f32(s): v = struct.unpack('>f' if s.be else '<f', s.b[s.p:s.p+4])[0]; s.p += 4; return v
    def f64(s): v = struct.unpack('>d' if s.be else '<d', s.b[s.p:s.p+8])[0]; s.p += 8; return v
    def cstr(s): e = s.b.index(b'\0', s.p); v = s.b[s.p:e].decode(); s.p = e + 1; return v
    def align(s, n=4): s.p = (s.p + n - 1) // n * n

def load(data):
    r = R(data, True)
    meta_size = r.u32(); file_size = r.u32(); version = r.u32(); data_off = r.u32()
    big = True
    if version >= 9:
        big = r.u8() == 0   # 0 = little endian? (endianness byte: 0 little, 1 big)
        r.p += 3
        big = False if data[r.p-4] == 0 else True
    if version >= 22:
        meta_size = r.u32(); file_size = r.i64(); data_off = r.i64(); r.p += 8
    r.be = big
    unity = r.cstr() if version >= 7 else ''
    platform = r.i32() if version >= 8 else 0
    typetree = r.u8() != 0 if version >= 13 else True
    ntypes = r.i32()
    types = []
    for _ in range(ntypes):
        cid = r.i32()
        if version >= 16: r.u8()
        if version >= 17: r.i16()
        if version >= 13:
            if (version < 16 and cid < 0) or (version >= 16 and cid == 114):
                r.p += 16
            r.p += 16
        nodes = None
        if typetree:
            nn = r.i32(); sl = r.i32()
            raw = []
            for _ in range(nn):
                v = r.u16(); lvl = r.u8(); fl = r.u8(); to = r.u32(); no = r.u32(); bs = r.i32(); idx = r.i32(); mf = r.i32()
                if version >= 19: r.p += 8
                raw.append((v, lvl, fl, to, no, bs, idx, mf))
            sb = data[r.p:r.p+sl]; r.p += sl
            if version >= 21:
                nd = r.i32(); r.p += 4 * nd
            def nm(o):
                return cstr_at(COMMON, o & 0x7fffffff) if o & 0x80000000 else cstr_at(sb, o)
            nodes = [dict(level=n[1], type=nm(n[3]), name=nm(n[4]), size=n[5], meta=n[7], flags=n[2]) for n in raw]
        types.append((cid, nodes))
    if 7 <= version < 14: r.i32()
    nobj = r.i32()
    objs = []
    for _ in range(nobj):
        if version >= 14: r.align(4); pid = r.i64()
        else: pid = r.i32()
        off = r.i64() if version >= 22 else r.u32()
        sz = r.u32(); tid = r.i32()
        if version < 16: cid = tid
        else: cid = types[tid][0]
        objs.append(dict(pid=pid, off=off + data_off, size=sz, tid=tid, cid=cid))
    return dict(version=version, unity=unity, platform=platform, typetree=typetree, types=types, objs=objs, data=data, be=big)

def read_value(r, nodes, i):
    """Returns (value, next_index)."""
    n = nodes[i]; t = n['type']; lvl = n['level']
    # child range
    j = i + 1
    while j < len(nodes) and nodes[j]['level'] > lvl: j += 1
    kids = list(range(i + 1, j))
    def aligned(): return bool(n['meta'] & 0x4000)
    if t == 'string':
        ln = r.i32(); v = r.b[r.p:r.p+ln].decode('utf8', 'replace'); r.p += ln; r.align(4); return v, j
    if t in ('SInt8',): v = struct.unpack('b', r.b[r.p:r.p+1])[0]; r.p += 1
    elif t in ('UInt8', 'char'): v = r.u8()
    elif t == 'bool': v = r.u8() != 0
    elif t == 'SInt16' or t == 'short': v = r.i16()
    elif t == 'UInt16' or t == 'unsigned short': v = r.u16()
    elif t == 'SInt32' or t == 'int': v = r.i32()
    elif t == 'UInt32' or t == 'unsigned int': v = r.u32()
    elif t == 'SInt64' or t == 'long long': v = r.i64()
    elif t == 'UInt64' or t == 'unsigned long long': v = r.i64()
    elif t == 'float': v = r.f32()
    elif t == 'double': v = r.f64()
    elif n['size'] == 4 and not kids: v = r.i32()
    elif n['size'] == 1 and not kids: v = r.u8()
    elif n['size'] == 2 and not kids: v = r.i16()
    elif kids and nodes[kids[0]]['type'] == 'Array' and t != 'TypelessData' or (t in ('vector', 'staticvector', 'set', 'map')):
        # container: first child is Array(size, data)
        ai = kids[0]
        arr = nodes[ai]
        a_kids = [k for k in range(ai + 1, len(nodes)) if nodes[k]['level'] > arr['level']]
        a_kids = [k for k in a_kids if nodes[k]['level'] > arr['level']]
        # find the end of array node subtree
        e = ai + 1
        while e < len(nodes) and nodes[e]['level'] > arr['level']: e += 1
        size = r.i32()
        di = ai + 2
        dn = nodes[di]
        if dn['type'] in ('UInt8', 'SInt8', 'char') and not [k for k in range(di+1, e)]:
            v = r.b[r.p:r.p+size]; r.p += size
        else:
            v = []
            for _ in range(size):
                x, _n = read_value(r, nodes, di); v.append(x)
        if aligned() or arr['meta'] & 0x4000: r.align(4)
        return v, j
    elif t == 'TypelessData':
        size = r.i32(); v = r.b[r.p:r.p+size]; r.p += size; r.align(4); return v, j
    else:
        d = {}
        k = i + 1
        while k < j:
            x, nk = read_value(r, nodes, k)
            d[nodes[k]['name']] = x
            k = nk
        if aligned(): r.align(4)
        return d, j
    if aligned(): r.align(4)
    return v, j

def read_obj(sf, o):
    types = sf['types']; nodes = types[o['tid']][1]
    r = R(sf['data'], sf['be']); r.p = o['off']
    v, _ = read_value(r, nodes, 0)
    return v
