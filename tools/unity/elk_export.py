import sys; sys.path.insert(0,'.')
import numpy as np, elk_extract as e
SCALE=0.85
R=np.array([[-1,0,0],[0,0,1],[0,1,0]],float)
def prep(lod=0):
    d=e.load(lod); nb=len(d['names'])
    Gr=[]  # rest global (4x4) godot space, scaled
    for b in range(nb):
        M=np.linalg.inv(d['bp'][b])
        B=M[:3,:3]/np.cbrt(abs(np.linalg.det(M[:3,:3])))
        G=np.eye(4); G[:3,:3]=R@B@R.T; G[:3,3]=R@M[:3,3]*SCALE
        Gr.append(G)
    V=(R@d['P'].T).T*SCALE; N=(R@d['N'].T).T
    idx=d['idx'].copy()
    a,b,c=V[idx[:,0]],V[idx[:,1]],V[idx[:,2]]
    fn=np.cross(b-a,c-a); nn=N[idx].sum(1)
    pos=(fn*nn).sum(1)>0   # Godot wants (b-a)x(c-a) against normal
    print('tris facing wrong',pos.sum(),'of',len(idx))
    if pos.mean()>0.5: idx[:,[1,2]]=idx[:,[2,1]]
    return d,Gr,V,N,idx
def pose(d,Gr,ang):
    nb=len(d['names']); par=d['parents']
    Gc=[None]*nb
    for b in range(nb):
        p=par[b]
        if p<0: L=Gr[b]
        else: L=np.linalg.inv(Gr[p])@Gr[b]
        if p<0: Pb=np.eye(3); Po=np.zeros(3)
        else: Pb=Gc[p][:3,:3]; Po=Gc[p][:3,3]
        Lb=L[:3,:3]; Lo=L[:3,3]
        th=ang.get(d['names'][b],0.0)
        G=np.eye(4)
        base=Pb@Lb
        if th:
            a=np.linalg.inv(base)@np.array([1.,0,0]); a/=np.linalg.norm(a)
            K=np.array([[0,-a[2],a[1]],[a[2],0,-a[0]],[-a[1],a[0],0]])
            Rm=np.eye(3)+np.sin(th)*K+(1-np.cos(th))*K@K
            G[:3,:3]=base@Rm
        else: G[:3,:3]=base
        G[:3,3]=Po+Pb@Lo
        Gc[b]=G
    return Gc
def skin(d,Gr,V,Gc):
    out=np.zeros_like(V)
    S=[Gc[b]@np.linalg.inv(Gr[b]) for b in range(len(Gc))]
    for k in range(4):
        for b in range(len(S)):
            m=d['I'][:,k]==b
            if m.any(): out[m]+=d['W'][m,k][:,None]*((S[b][:3,:3]@V[m].T).T+S[b][:3,3])
    return out
