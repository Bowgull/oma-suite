import math, wave, struct, random
random.seed(7); SR=44100
def note(n): return 440*2**((n-69)/12)
def osc(k,f,t,duty):
    ph=(f*t)%1
    if k=='sq': return 1 if ph<duty else -1
    if k=='tri': return 4*abs(ph-.5)-1
    return math.sin(2*math.pi*ph)
L=6.6; buf=[0.0]*int(SR*L)
def tone(st,dur,midi,k,vol,duty=.5,ring=.06,soft=False):
    f=note(midi); s0=int(st*SR)
    for i in range(int((dur+ring)*SR)):
        t=i/SR; a=min(1,t/.005)
        e=a if t<dur else a*math.exp(-(t-dur)/(ring/5))
        if soft:
            b=math.exp(-t/.6); v=osc('sq',f,t,duty)*b*.6+math.sin(2*math.pi*f*t)*(1-b*.6)
        else: v=osc(k,f,t,duty)
        j=s0+i
        if j<len(buf): buf[j]+=v*vol*e
def noise(st,dur,v0,v1,decay=None):
    s0=int(st*SR); lp=0
    for i in range(int(dur*SR)):
        t=i/SR; lp+= .25*(random.uniform(-1,1)-lp)
        v=(v0+(v1-v0)*t/dur) if decay is None else v0*math.exp(-t/decay)
        j=s0+i
        if j<len(buf): buf[j]+=lp*v
C=72; e=.14
def chord(st,dur,notes,bass,vol=1):
    for n in notes: tone(st,dur*.95,n,'sq',.16*vol,.25)
    tone(st,dur*.95,bass,'tri',.5*vol)
# phrase 1, home chord then IV: C E G -> A (held)
t=0
for m in [C,C+4,C+7]: tone(t,e*.9,m,'sq',.36,.5); t+=e
chord(0,3*e,[C-8,C-5],48,.8)
tone(t,3*e,C+9,'sq',.4,.5); chord(t,3*e,[C-7,C-3],41,.85); t+=3*e
# phrase 2, the dominant: B D F -> G (held), a step higher and louder
t+=.04
for m in [C-1,C+2,C+5]: tone(t,e*.9,m,'sq',.4,.5); t+=e
chord(t-3*e,3*e,[C-5,C-1],43,.9)
tone(t,2.5*e,C+7,'sq',.44,.5); chord(t,2.5*e,[C-1,C+2,C+5],43,1); t+=2.5*e
# the climb: G A B, louder each step, a drum roll swelling underneath
t+=.03; roll=t
for i,m in enumerate([C+7,C+9,C+11]):
    v=.8+.12*i; tone(t,e*.92,m,'sq',.44*v,.5); tone(t,e*.92,m-12,'sq',.18*v,.25); tone(t,e*.92,43,'tri',.55*v); t+=e
noise(roll,t-roll,.03,.22)
t+=.03
# home: C major, rings ~3.5 s, a soft crash, a slow chord shimmer (steady pitches, no wobble)
H=t
for m,v,du in [(C+12,.42,.5),(C+7,.2,.25),(C+4,.2,.25),(C,.16,.5),(C+24,.08,.5)]:
    tone(H,.7,m,'sq',v,du,ring=3.4,soft=True)
tone(H,.7,36,'tri',.6,ring=4.5); tone(H,.7,48,'tri',.32,ring=4.5)
noise(H,1.6,.2,0,decay=.35)
for i,m in enumerate([C+12,C+16,C+19,C+24,C+19,C+16,C+12,C+16,C+19,C+24]):
    st=H+.35+i*.22; tone(st,.05,m,'tri',.12*math.exp(-i/5),ring=.5)
d=int(.17*SR); out=buf[:]
for i in range(d,len(out)): out[i]+=out[i-d]*.22
m=max(abs(x) for x in out)
w=wave.open('B4.wav','w'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
w.writeframes(b''.join(struct.pack('<h',int(x/m*.8*32767)) for x in out)); w.close()
print('home at',round(H,2))
