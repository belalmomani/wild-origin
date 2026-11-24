import numpy as np
TAB=[(2,8),(5,17),(9,29),(13,42),(18,60),(24,80),(33,106),(47,183)]
DIST=[3,6,11,16,23,32,41,64]
def c(v): return 0 if v<0 else 255 if v>255 else int(v)
def x4(v): return (v<<4)|v
def x5(v): return (v<<3)|(v>>2)
def x6(v): return (v<<2)|(v>>4)
def x7(v): return (v<<1)|(v>>6)
def block(b):
    b0,b1,b2,b3,b4,b5,b6,b7=b
    msb=(b4<<8)|b5; lsb=(b6<<8)|b7
    out=[None]*16  # index x*4+y
    def sel(p): return (((msb>>p)&1)<<1)|((lsb>>p)&1)
    diff=(b3>>1)&1
    if diff==0:
        c1=(x4(b0>>4),x4(b1>>4),x4(b2>>4)); c2=(x4(b0&15),x4(b1&15),x4(b2&15))
        mode='e'
    else:
        R=b0>>3; G=b1>>3; B=b2>>3
        dR=b0&7; dG=b1&7; dB=b2&7
        if dR>=4: dR-=8
        if dG>=4: dG-=8
        if dB>=4: dB-=8
        R2=R+dR; G2=G+dG; B2=B+dB
        if R2<0 or R2>31: mode='T'
        elif G2<0 or G2>31: mode='H'
        elif B2<0 or B2>31: mode='P'
        else:
            mode='e'; c1=(x5(R),x5(G),x5(B)); c2=(x5(R2),x5(G2),x5(B2))
    if mode=='e':
        t1=(b3>>5)&7; t2=(b3>>2)&7; flip=b3&1
        for x in range(4):
            for y in range(4):
                p=x*4+y
                sub2=(y>=2) if flip else (x>=2)
                col=c2 if sub2 else c1; t=TAB[t2 if sub2 else t1]
                s=sel(p); m=[t[0],t[1],-t[0],-t[1]][s]
                out[p]=(c(col[0]+m),c(col[1]+m),c(col[2]+m))
        return out
    if mode=='T':
        r1=((b0&0x18)>>1)|(b0&3); g1=b1>>4; bb1=b1&15; r2=b2>>4; g2=b2&15; bb2=b3>>4
        d=DIST[((b3&0x0c)>>1)|(b3&1)]
        a=(x4(r1),x4(g1),x4(bb1)); bcol=(x4(r2),x4(g2),x4(bb2))
        pal=[a,tuple(c(v+d) for v in bcol),bcol,tuple(c(v-d) for v in bcol)]
        for p in range(16): out[p]=pal[sel(p)]
        return out
    if mode=='H':
        r1=(b0&0x78)>>3; g1=((b0&7)<<1)|((b1&0x10)>>4)
        bb1=(b1&8)|((b1&3)<<1)|((b2&0x80)>>7)
        r2=(b2&0x78)>>3; g2=((b2&7)<<1)|((b3&0x80)>>7); bb2=(b3&0x78)>>3
        v1=(r1<<8)|(g1<<4)|bb1; v2=(r2<<8)|(g2<<4)|bb2
        di=(b3&4)|((b3&1)<<1)
        if v1>=v2: di|=1
        d=DIST[di]
        a=(x4(r1),x4(g1),x4(bb1)); bcol=(x4(r2),x4(g2),x4(bb2))
        pal=[tuple(c(v+d) for v in a),tuple(c(v-d) for v in a),tuple(c(v+d) for v in bcol),tuple(c(v-d) for v in bcol)]
        for p in range(16): out[p]=pal[sel(p)]
        return out
    ro=(b0&0x7e)>>1; go=((b0&1)<<6)|((b1&0x7e)>>1)
    bo=((b1&1)<<5)|(b2&0x18)|((b2&3)<<1)|((b3&0x80)>>7)
    rh=((b3&0x7c)>>1)|(b3&1); gh=(b4&0xfe)>>1; bh=((b4&1)<<5)|((b5&0xf8)>>3)
    rv=((b5&7)<<3)|((b6&0xe0)>>5); gv=((b6&0x1f)<<2)|((b7&0xc0)>>6); bv=b7&0x3f
    RO,GO,BO=x6(ro),x7(go),x6(bo); RH,GH,BH=x6(rh),x7(gh),x6(bh); RV,GV,BV=x6(rv),x7(gv),x6(bv)
    for x in range(4):
        for y in range(4):
            out[x*4+y]=(c((x*(RH-RO)+y*(RV-RO)+4*RO+2)>>2),c((x*(GH-GO)+y*(GV-GO)+4*GO+2)>>2),c((x*(BH-BO)+y*(BV-BO)+4*BO+2)>>2))
    return out
def decode(data,w,h):
    img=np.zeros((h,w,3),np.uint8)
    n=0
    for by in range(h//4):
        for bx in range(w//4):
            px=block(data[n:n+8]); n+=8
            for x in range(4):
                for y in range(4):
                    img[by*4+y,bx*4+x]=px[x*4+y]
    return img
