import sys, struct, glob, numpy as np
sys.path.insert(0,'/tmp/claude-0/-home-claude/302556f8-de18-54a8-ab50-fe96528e1ecb/scratchpad/unity')
import ufs, ser

def quat_mat(q):
    x,y,z,w=q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])

def load(lod=0):
    f=glob.glob('/mnt/user-data/attachments/*/f8a663cf*')[0]
    bun=ufs.read_bundle(f); cab=[x for x in bun if not x.endswith('.resS')][0]
    sf=ser.load(bun[cab]); byp={o['pid']:o for o in sf['objs']}
    res=bun[cab+'.resS']
    rd=lambda pid: ser.read_obj(sf,byp[pid])
    smr_pid={0:-4331696256261968143,1:140207805549162225}[lod]
    smr=rd(smr_pid); mesh=rd(smr['m_Mesh']['m_PathID'])
    # transforms
    def tw(tpid, cache={}):
        if tpid in cache: return cache[tpid]
        t=rd(tpid); L=np.eye(4)
        q=t['m_LocalRotation']; p=t['m_LocalPosition']; s=t['m_LocalScale']
        L[:3,:3]=quat_mat((q['x'],q['y'],q['z'],q['w']))*np.array([s['x'],s['y'],s['z']])
        L[:3,3]=[p['x'],p['y'],p['z']]
        fa=t['m_Father']['m_PathID']
        W=(tw(fa) if fa!=0 else np.eye(4))@L
        cache[tpid]=W; return W
    bones=smr['m_Bones']; names=[]; parents=[]; locals_=[]; worlds=[]
    pids=[b['m_PathID'] for b in bones]
    for pid in pids:
        t=rd(pid); g=rd(t['m_GameObject']['m_PathID']); names.append(g['m_Name'])
        worlds.append(tw(pid))
        q=t['m_LocalRotation']; p=t['m_LocalPosition']; s=t['m_LocalScale']
        locals_.append(((q['x'],q['y'],q['z'],q['w']),(p['x'],p['y'],p['z']),(s['x'],s['y'],s['z'])))
        fa=t['m_Father']['m_PathID']; parents.append(pids.index(fa) if fa in pids else -1)
    vd=mesh['m_VertexData']; n=vd['m_VertexCount']; data=vd['m_DataSize']; ch=vd['m_Channels']
    # stream layout
    strides={}
    for c in ch:
        if c['dimension']:
            sz={0:4,1:2,2:1,3:1,4:2,5:2,6:1,7:1,8:2,9:2,10:4,11:4}[c['format']]
            strides[c['stream']]=max(strides.get(c['stream'],0),c['offset']+sz*(c['dimension'] & 0xf))
    base={}; off=0
    for s_ in sorted(strides):
        base[s_]=off; off+=(strides[s_]*n+15)//16*16
    def chan(i):
        c=ch[i]; dim=c['dimension']&0xf
        dt={0:'<f4',1:'<f2',2:'u1',3:'i1',4:'<u2',5:'<i2',6:'u1',7:'i1',8:'<u2',9:'<i2',10:'<u4',11:'<i4'}[c['format']]
        isz=np.dtype(dt).itemsize
        out=np.zeros((n,dim),dtype=dt)
        for k in range(n):
            o=base[c['stream']]+k*strides[c['stream']]+c['offset']
            out[k]=np.frombuffer(data,dtype=dt,count=dim,offset=o)
        return out
    P=chan(0).astype(float); N=chan(1).astype(float); UV=chan(4).astype(float)
    W=chan(12).astype(float); I=chan(13).astype(int)
    idx=np.frombuffer(mesh['m_IndexBuffer'],dtype='<u2').astype(int).reshape(-1,3)
    bp=[]
    for m in mesh['m_BindPose']:
        bp.append(np.array([[m['e%d%d'%(r,c)] for c in range(4)] for r in range(4)]))
    # texture
    tex_pid=[o['pid'] for o in sf['objs'] if o['cid']==28]
    texs={rd(p)['m_Name']:rd(p) for p in tex_pid}
    return dict(names=names,parents=parents,locals=locals_,worlds=worlds,P=P,N=N,UV=UV,W=W,I=I,idx=idx,bp=bp,texs=texs,res=res)

if __name__=='__main__':
    d=load(0)
    print(d['P'].shape,d['idx'].shape,d['W'].sum(1)[:5], d['I'][:3])
    rest=np.zeros_like(d['P'])
    for k in range(4):
        for b in range(34):
            m=(d['I'][:,k]==b)
            if not m.any(): continue
            M=d['worlds'][b]@d['bp'][b]
            rest[m]+= (d['W'][m,k][:,None]) * ((M[:3,:3]@d['P'][m].T).T+M[:3,3])
    print('rest min',rest.min(0).round(2),'max',rest.max(0).round(2))
    print('mesh min',d['P'].min(0).round(2),'max',d['P'].max(0).round(2))
    print(d['names']); print(d['parents'])
    print({k:(v['m_Width'],v['m_Height'],v['m_TextureFormat']) for k,v in d['texs'].items()})
