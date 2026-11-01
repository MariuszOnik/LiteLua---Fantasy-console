"""Style editor on the PC: the map as the 3DS shows it from above, with sliders for the
style's `view` part (fog, borders, names, the selection's light and its swell). Saves
style.lua for the 3DS's SD card (sdmc:/3ds/heroes3d/style.lua: read over romfs at start,
no build needed) or back into styles/.

  python HeroesDS/tools/styler.py [--style styles/leather.lua]
                                  [--scenario scenarios/six-realms.lua] [--seed 77 ...]
                                  [--sd E:/3ds/heroes3d/style.lua]   (a real card)

Opens http://127.0.0.1:8765 in the browser. The `map` part (paper, lines in the
textures) is baked by make_m3.py: the editor shows it but keeps it as it is. Not
shown: the GPU paper grain, the 3D tilt; the gap by the border is the 3DS's least.
"""
import argparse
import base64
import io
import json
import os
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import make_m3  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # HeroesDS
SD_STYLE = os.path.join(os.environ.get("APPDATA", ""), "Azahar", "sdmc", "3ds", "heroes3d", "style.lua")
SIZE = 1024


def lua_value(v, indent=""):
    """A value as Lua data (the subset of D38): tables, strings, numbers, booleans."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(round(v, 4)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return make_m3.lua_str(v)
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua_value(x) for x in v) + " }"
    inner = indent + "  "
    items = ["%s%s = %s," % (inner, k, lua_value(x, inner)) for k, x in v.items()]
    return "{\n" + "\n".join(items) + "\n" + indent + "}"


def png(arr):
    from PIL import Image
    buf = io.BytesIO()
    Image.fromarray(arr).save(buf, "PNG")
    return buf.getvalue()


def prepare(a):
    """The map picture (no owners' colours), region index per pixel, regions, realms."""
    import lsong
    m = make_m3.m2.generate(a.seed, a.size, a.provinces, a.coast)
    regions, counties, _, chains = make_m3.build(m)
    with open(a.style, encoding="utf-8") as f:
        text = f.read()
    data = lsong.parse_lua(text)
    style, folder = make_m3.load_style(a.style)
    scen = (make_m3.load_scenario(a.scenario, regions, counties) if a.scenario
            else make_m3.default_scenario(m, regions, counties))
    land = [i for i, c in enumerate(counties) if regions[c["region"]]["kind"] != make_m3.KIND_SEA]
    print("painting the map (a few seconds) ...", flush=True)
    painter = make_m3.Painter(m, counties, chains, style, folder)
    rgb, ids = painter.paint(0, 0, painter.world, SIZE, land)
    lut = np.full(make_m3.NO_REGION + 1, 0xFFFF, np.uint32)
    lut[:len(counties)] = [c["region"] for c in counties]
    reg = lut[ids[0]]
    idimg = np.stack([reg & 255, reg >> 8, np.zeros_like(reg)], -1).astype(np.uint8)
    realm_ix = {r["id"]: i for i, r in enumerate(scen["realms"])}
    owner = {e["id"]: realm_ix.get(e.get("owner") or "", -1) for e in scen["provinces"]}
    names = {e["id"]: e["name"] for e in scen["provinces"]}
    k = SIZE / painter.world
    index = {r["id"]: i for i, r in enumerate(regions)}   # neighbours are listed by id
    out = []
    for r in regions:
        out.append(dict(kind=r["kind"], owner=owner.get(r["id"], -1) if r["kind"] == make_m3.KIND_LAND else -1,
                        name=names.get(r["id"], r["name"]), neigh=[index[n] for n in r["neigh"] if n in index],
                        x=(r["cx"] + painter.world / 2) * k, y=(r["cz"] + painter.world / 2) * k))
    return dict(paper=png(rgb[0]), ids=png(idimg),
                info=dict(regions=out, realms=scen["realms"], player=realm_ix.get(scen.get("player"), 0),
                          fog=bool(scen.get("fog", True)), view=data.get("view", {}),
                          cellPx=k, styleName=os.path.basename(a.style)),
                map=data.get("map", {}), style_path=os.path.abspath(a.style))


PAGE = r"""<!doctype html><html><head><meta charset="utf-8"><title>Style editor</title>
<style>
body{margin:0;font:13px sans-serif;display:flex;height:100vh;background:#222;color:#ddd}
#side{width:340px;overflow-y:auto;padding:8px 12px;background:#2b2b2b}
#main{flex:1;overflow:hidden}
canvas{width:100%;height:100%;cursor:crosshair;display:block}
h3{margin:12px 0 4px;color:#fc6;font-size:13px}
.row{display:flex;align-items:center;gap:6px;margin:3px 0}
.row label{width:96px} .row input[type=range]{flex:1} .row span{width:38px;text-align:right}
button{margin:4px 4px 0 0;padding:5px 8px} small{color:#999}
textarea{width:100%;height:160px;font:11px monospace;background:#111;color:#cfc}
</style></head><body>
<div id="side">
<b id="title"></b><br><small>Click a province to select it; the wheel zooms, drag pans, a double click fits. The map part (paper, lines) comes from make_m3.py.</small>
<div id="ctl"></div>
<h3>Save</h3>
<button onclick="save('sd')">Save to SD</button><button onclick="save('style')">Save to styles/</button>
<div id="msg"></div>
<textarea id="out" readonly></textarea>
</div>
<div id="main"><canvas id="cv"></canvas></div>
<script>
const info = __INFO__;
const V = info.view;
// the 3DS's defaults (main.c) for whatever the style leaves out
const D = {background:[150,190,200], tint:0.62, neutral:[190,180,160],
  fog:{unseen:[102,102,119,204], seen:[153,153,153,102]},
  border:{show:true, color:[107,20,15], alpha:0.85, width:1, pattern:"-", dash:8},
  labels:{province:[20,12,4], county:[70,50,30], shadow:[40,25,15], selected:[255,255,255]},
  select:{mode:"glow", pattern:"-----  ", color:[40,25,15], alpha:0.9, width:1.6, dash:5, fill:0,
          flicker:0, period:3.5, gap:0.1, soft:3, light:[255,250,235]},
  grain:{strength:0, cells:3}};
function merge(d, v){ if (v===undefined) return d; if (Array.isArray(d)||typeof d!=="object") return v;
  const o={}; for (const k in d) o[k]=merge(d[k], v[k]); for (const k in v) if (!(k in o)) o[k]=v[k]; return o; }
const S = merge(D, V);
document.getElementById("title").textContent = "Style: " + info.styleName;

// controls: [path, label, kind, min, max, step]
const C = [
 ["h","Map"], ["background","background","rgb"], ["tint","realm colour","num",0,1,0.01], ["neutral","nobody's land","rgb"],
 ["h","Fog"], ["fogOn","fog on","bool"], ["fogRing","seen-before ring","bool"], ["fog.unseen","never seen","rgba"], ["fog.seen","seen before","rgba"],
 ["h","Realms' borders"], ["border.show","show","bool"], ["border.color","colour","rgb"], ["border.alpha","alpha","num",0,1,0.01], ["border.width","width","num",0.2,4,0.1],
 ["h","Names"], ["labels.province","province","rgb"], ["labels.shadow","realm shadow","rgb"], ["labels.selected","selected","rgb"],
 ["h","Selection"], ["select.mode","mode","choice",["fill","glow","line","none"]],
 ["select.fill","fill (light)","num",0,1,0.01], ["select.flicker","flicker (fade)","num",0,1,0.01],
 ["select.period","period (s)","num",0.5,10,0.1], ["select.soft","soft (x gap)","num",0,8,0.1],
 ["select.gap","gap (cells)","num",0,1,0.01], ["select.light","light","rgb"],
];
S.fogOn = info.fog; S.fogRing = false;
function get(p){ return p.split(".").reduce((o,k)=>o[k], S); }
function set(p,v){ const ks=p.split("."); let o=S; for (let i=0;i<ks.length-1;i++) o=o[ks[i]]; o[ks.at(-1)]=v; }
const hex = c => "#"+c.slice(0,3).map(x=>(+x).toString(16).padStart(2,"0")).join("");
const unhex = h => [1,3,5].map(i=>parseInt(h.substr(i,2),16));
const ctl = document.getElementById("ctl");
for (const c of C) {
  if (c[0]==="h") { const h=document.createElement("h3"); h.textContent=c[1]; ctl.appendChild(h); continue; }
  const [p,label,kind] = c, row=document.createElement("div"); row.className="row";
  row.innerHTML = "<label>"+label+"</label>"; ctl.appendChild(row);
  const changed = () => { dirty=true; if (p.startsWith("select")) selDirty=true; writeOut(); };
  if (kind==="num") {
    const r=document.createElement("input"); r.type="range"; r.min=c[3]; r.max=c[4]; r.step=c[5]; r.value=get(p);
    const sp=document.createElement("span"); sp.textContent=get(p);
    r.oninput=()=>{ set(p,+r.value); sp.textContent=r.value; changed(); }; row.append(r,sp);
  } else if (kind==="rgb"||kind==="rgba") {
    const i=document.createElement("input"); i.type="color"; i.value=hex(get(p)); row.appendChild(i);
    i.oninput=()=>{ const v=get(p), n=unhex(i.value); set(p, kind==="rgba"?[...n,v[3]]:n); changed(); };
    if (kind==="rgba") { const r=document.createElement("input"); r.type="range"; r.min=0; r.max=255; r.value=get(p)[3];
      const sp=document.createElement("span"); sp.textContent=r.value;
      r.oninput=()=>{ const v=get(p).slice(); v[3]=+r.value; set(p,v); sp.textContent=r.value; changed(); }; row.append(r,sp); }
  } else if (kind==="bool") {
    const i=document.createElement("input"); i.type="checkbox"; i.checked=get(p); i.onchange=()=>{ set(p,i.checked); changed(); }; row.appendChild(i);
  } else {
    const s=document.createElement("select"); for (const o of c[3]) s.add(new Option(o,o)); s.value=get(p);
    s.onchange=()=>{ set(p,s.value); changed(); }; row.appendChild(s);
  }
}

// --- the map --------------------------------------------------------------------------
const cv=document.getElementById("cv"), cx=cv.getContext("2d"), main=document.getElementById("main");
let W, paper, rid, base, mapCv, mapCx, dirty=true, selDirty=true, selected=-1, selPix=null, selBand=null, baseFog;
let zoom=1, ox=0, oy=0;   // screen = map pixel * zoom + (ox, oy)
const R = info.regions, NONE=0xFFFF;
function load(src){ return new Promise(ok=>{ const im=new Image(); im.onload=()=>ok(im); im.src=src; }); }
Promise.all([load("paper.png"), load("ids.png")]).then(([p, ids])=>{
  W=p.width; mapCv=new OffscreenCanvas(W,W); mapCx=mapCv.getContext("2d");
  const t=new OffscreenCanvas(W,W).getContext("2d");
  t.drawImage(p,0,0); paper=t.getImageData(0,0,W,W).data;
  t.drawImage(ids,0,0); const d=t.getImageData(0,0,W,W).data;
  rid=new Uint16Array(W*W); for (let i=0;i<W*W;i++) rid[i]=d[i*4]|d[i*4+1]<<8;
  base=new ImageData(W,W); fit(); writeOut(); requestAnimationFrame(frame);
});

// zoom: the wheel round the pointer, drag pans, a double click fits the map again
function fit(){ cv.width=main.clientWidth; cv.height=main.clientHeight;
  zoom=Math.min(cv.width,cv.height)/W; ox=(cv.width-W*zoom)/2; oy=(cv.height-W*zoom)/2; }
window.onresize=()=>{ const cxm=(cv.width/2-ox)/zoom, cym=(cv.height/2-oy)/zoom;
  cv.width=main.clientWidth; cv.height=main.clientHeight; ox=cv.width/2-cxm*zoom; oy=cv.height/2-cym*zoom; };
cv.onwheel=e=>{ e.preventDefault(); const r=cv.getBoundingClientRect(), x=e.clientX-r.left, y=e.clientY-r.top;
  const k=Math.min(16,Math.max(0.3,zoom*(e.deltaY<0?1.2:1/1.2)))/zoom;
  ox=x-(x-ox)*k; oy=y-(y-oy)*k; zoom*=k; };
let drag=null;
cv.onmousedown=e=>{ drag={x:e.clientX, y:e.clientY, ox, oy, moved:false}; };
window.onmousemove=e=>{ if (!drag) return; const dx=e.clientX-drag.x, dy=e.clientY-drag.y;
  if (Math.abs(dx)+Math.abs(dy)>4) drag.moved=true; if (drag.moved){ ox=drag.ox+dx; oy=drag.oy+dy; } };
window.onmouseup=e=>{ if (drag&&!drag.moved&&e.target===cv){ const r=cv.getBoundingClientRect(),
    x=Math.floor((e.clientX-r.left-ox)/zoom), y=Math.floor((e.clientY-r.top-oy)/zoom);
    if (x>=0&&y>=0&&x<W&&y<W){ const g=rid[y*W+x]; selected = g===NONE||g===selected ? -1 : g; selDirty=true; } }
  drag=null; };
cv.ondblclick=fit;

function fogState(){
  // as on the 3DS at the start: own provinces and their neighbours (land and sea) seen
  // now, the rest never; fogRing also shows the land next to that as seen before
  const f=new Uint8Array(R.length).fill(S.fogOn?0:2); if (!S.fogOn) return f;
  R.forEach((g,i)=>{ if (g.kind===0&&g.owner===info.player){ f[i]=2; for (const n of g.neigh) f[n]=2; } });
  if (S.fogRing) R.forEach((g,i)=>{ if (f[i]===2&&g.kind!==1) for (const n of g.neigh) if (!f[n]&&R[n].kind!==1) f[n]=1; });
  return f;
}
// a box blur of an RGBA float layer, both ways (the 3DS's fog texture is 512 wide and
// filtered: soft edges about two of these pixels wide)
function blur(a, r){ const n=W, tmp=new Float32Array(a.length);
  for (const [src,dst,step,lineStep] of [[a,tmp,4,n*4],[tmp,a,n*4,4]])
    for (let l=0;l<n;l++){ const acc=[0,0,0,0], b0=l*lineStep;
      for (let k=-r;k<=r;k++){ const i=b0+Math.min(n-1,Math.max(0,k))*step; for (let c=0;c<4;c++) acc[c]+=src[i+c]; }
      for (let k=0;k<n;k++){ for (let c=0;c<4;c++) dst[b0+k*step+c]=acc[c]/(2*r+1);
        const out=b0+Math.max(0,k-r)*step, inn=b0+Math.min(n-1,k+r+1)*step;
        for (let c=0;c<4;c++) acc[c]+=src[inn+c]-src[out+c]; } }
}
function rebuild(){
  const out=base.data, k=S.tint, fog=fogState(), tint=R.map(g=>{
    if (g.kind===1) return [255,255,255];
    if (g.kind===2||g.owner<0) return S.neutral;
    const c=info.realms[g.owner].color; return c.map(v=>k*v+(1-k)*255); });
  const ownerOf = i => R[i].kind===0 ? R[i].owner : -1;
  for (let i=0;i<W*W;i++){ const g=rid[i], t=g===NONE?[255,255,255]:tint[g];
    for (let c=0;c<3;c++) out[i*4+c]=paper[i*4+c]*t[c]/255; out[i*4+3]=255; }
  if (S.border.show){ // realms' borders: pixels where land of two owners meets, widened
    const rad=Math.max(1,Math.round(S.border.width*1.6)), a=S.border.alpha, col=S.border.color, edge=[];
    for (let y=0;y<W-1;y++) for (let x=0;x<W-1;x++){ const i=y*W+x, g=rid[i];
      for (const j of [i+1,i+W]){ const h=rid[j]; if (g===NONE||h===NONE||g===h) continue;
        if (R[g].kind===1||R[h].kind===1||ownerOf(g)===ownerOf(h)||!fog[g]||!fog[h]) continue; edge.push(i); } }
    const mark=new Uint8Array(W*W);
    for (const i of edge){ const x=i%W, y=(i/W)|0;
      for (let dy=-rad;dy<=rad;dy++) for (let dx=-rad;dx<=rad;dx++){ if (dx*dx+dy*dy>rad*rad) continue;
        const X=x+dx, Y=y+dy; if (X>=0&&Y>=0&&X<W&&Y<W) mark[Y*W+X]=1; } }
    for (let i=0;i<W*W;i++) if (mark[i]) for (let c=0;c<3;c++) out[i*4+c]+= (col[c]-out[i*4+c])*a;
  }
  // fog: colours as the 3DS keeps them (4 bits each, RGBA4), premultiplied, blurred
  const q4 = v => (v>>4)*17, layer=new Float32Array(W*W*4);
  const look=[S.fog.unseen.map(q4), S.fog.seen.map(q4)];
  for (let i=0;i<W*W;i++){ const g=rid[i]; if (g===NONE||fog[g]===2) continue; const c=look[fog[g]], a=c[3]/255;
    layer[i*4]=c[0]*a; layer[i*4+1]=c[1]*a; layer[i*4+2]=c[2]*a; layer[i*4+3]=a; }
  blur(layer, Math.max(1, Math.round(W/512)));
  for (let i=0;i<W*W;i++){ const a=layer[i*4+3]; if (a<=0) continue;
    for (let c=0;c<3;c++) out[i*4+c]=out[i*4+c]*(1-a)+layer[i*4+c]; }
  baseFog=fog;
}
function selection(){
  // the selected region's pixels and the band each is in (0 far .. 4 by the border),
  // from a distance-to-the-border pass over its pixels
  selPix=null; if (selected<0) return;
  const px=[]; for (let i=0;i<W*W;i++) if (rid[i]===selected) px.push(i);
  const dist=new Float32Array(W*W).fill(1e9), q=[];
  for (const i of px){ const x=i%W, y=(i/W)|0;
    if (x===0||y===0||x===W-1||y===W-1||rid[i-1]!==selected||rid[i+1]!==selected||rid[i-W]!==selected||rid[i+W]!==selected){ dist[i]=0.5; q.push(i); } }
  for (let h=0;h<q.length;h++){ const i=q[h], d=dist[i]+1;
    for (const j of [i-1,i+1,i-W,i+W]) if (j>=0&&j<W*W&&rid[j]===selected&&dist[j]>d){ dist[j]=d; q.push(j); } }
  const g=S.select.gap*info.cellPx, sb=S.select.soft;
  selPix=px; selBand=px.map(i=>{ let b=0; for (let k=1;k<=4;k++) if (dist[i]<g*(1+sb*(4-k)/3)) b=k; return b; });
}
function frame(t){
  if (dirty){ rebuild(); dirty=false; selDirty=true; }
  if (selDirty){ selection(); selDirty=false; }
  const img=new ImageData(new Uint8ClampedArray(base.data), W);
  const o=img.data, s=S.select;
  if (selPix && s.mode!=="none"){
    if (s.mode==="glow"){ const a=0.18+0.1*Math.sin(t/1000*7.2);
      for (const i of selPix) for (let c=0;c<3;c++) o[i*4+c]+=([255,255,230][c]-o[i*4+c])*a;
      selPix.forEach((i,n)=>{ if (selBand[n]>=4) for (let c=0;c<3;c++) o[i*4+c]=[255,242,153][c]; });
    } else {
      const amount=s.fill*(1-s.flicker*(1-Math.sin(t/1000*2*Math.PI/s.period))/2);
      selPix.forEach((i,n)=>{ const a=amount*(4-selBand[n])/4; for (let c=0;c<3;c++) o[i*4+c]*=1+a*s.light[c]/255; });
    }
  }
  mapCx.putImageData(img,0,0);
  cx.setTransform(1,0,0,1,0,0); cx.fillStyle="rgb("+S.background+")"; cx.fillRect(0,0,cv.width,cv.height);
  cx.imageSmoothingEnabled=true; cx.setTransform(zoom,0,0,zoom,ox,oy); cx.drawImage(mapCv,0,0);
  cx.setTransform(1,0,0,1,0,0); labels();
  requestAnimationFrame(frame);
}
function labels(){
  // names as on the 3DS by distance: realms far, provinces nearer
  cx.textAlign="center"; cx.textBaseline="middle";
  const seen=new Map(), z=Math.min(2.5,Math.max(0.6,zoom)), sx=x=>x*zoom+ox, sy=y=>y*zoom+oy;
  R.forEach((g,i)=>{ if (g.kind!==0||!baseFog[i]) return;
    if (zoom>0.45||i===selected){ cx.font=(i===selected?"bold ":"")+Math.round(13*z)+"px sans-serif";
      cx.fillStyle="rgb("+(i===selected?S.labels.selected:S.labels.province)+")"; cx.fillText(g.name,sx(g.x),sy(g.y)); }
    if (g.owner>=0){ const s=seen.get(g.owner)||[0,0,0]; seen.set(g.owner,[s[0]+g.x,s[1]+g.y,s[2]+1]); } });
  if (zoom>2) return;
  cx.font="bold "+Math.round(30*Math.min(1.4,Math.max(0.5,zoom*1.2)))+"px sans-serif";
  for (const [f,[x,y,n]] of seen){ const r=info.realms[f]; if (n<2) continue;
    const name=r.city?r.name:r.name.toUpperCase(), X=sx(x/n), Y=sy(y/n)-20;
    cx.fillStyle="rgba("+S.labels.shadow+",0.6)"; cx.fillText(name,X+3,Y+3);
    cx.fillStyle="rgb("+r.color.map(v=>v*0.5+128).map(Math.round)+")"; cx.fillText(name,X,Y); }
}

// --- style.lua ------------------------------------------------------------------------
function lua(v, ind){ ind=ind||"";
  if (typeof v==="boolean"||typeof v==="number") return String(typeof v==="number"?Math.round(v*1000)/1000:v);
  if (typeof v==="string") return JSON.stringify(v);
  if (Array.isArray(v)) return "{ "+v.map(x=>lua(x)).join(", ")+" }";
  const i2=ind+"  "; return "{\n"+Object.keys(v).map(k=>i2+k+" = "+lua(v[k],i2)+",").join("\n")+"\n"+ind+"}"; }
function viewOut(){ const v=JSON.parse(JSON.stringify(S)); delete v.fogOn; delete v.fogRing; return v; }
function writeOut(){ document.getElementById("out").value = "  view = "+lua(viewOut(),"  ")+","; }
async function save(target){
  const r = await fetch("save?target="+target, {method:"POST", body: JSON.stringify(viewOut())});
  document.getElementById("msg").textContent = await r.text();
}
</script></body></html>"""


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--style", default=os.path.join(HERE, "styles", "leather.lua"))
    p.add_argument("--scenario", default=os.path.join(HERE, "scenarios", "six-realms.lua"))
    p.add_argument("--seed", type=int, default=77)
    p.add_argument("--size", type=int, default=72)
    p.add_argument("--provinces", type=int, default=45)
    p.add_argument("--coast", type=float, default=1.0)
    p.add_argument("--port", type=int, default=8765)
    p.add_argument("--sd", default=SD_STYLE, help="where 'Save to SD' writes (default: Azahar's SD)")
    a = p.parse_args()
    d = prepare(a)
    page = PAGE.replace("__INFO__", json.dumps(d["info"])).encode()

    def style_text(view):
        return ("-- Made by tools/styler.py from %s; see classic.lua for every field.\nreturn {\n"
                "  map = %s,\n  view = %s,\n}\n" % (d["info"]["styleName"], lua_value(d["map"], "  "),
                                                    lua_value(view, "  ")))

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def send(self, body, kind="text/plain; charset=utf-8", code=200):
            self.send_response(code)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            path = self.path.split("?")[0]
            if path == "/":
                self.send(page, "text/html; charset=utf-8")
            elif path == "/paper.png":
                self.send(d["paper"], "image/png")
            elif path == "/ids.png":
                self.send(d["ids"], "image/png")
            else:
                self.send(b"not found", code=404)

        def do_POST(self):
            view = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            target = a.sd if "target=sd" in self.path else d["style_path"]
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "w", encoding="utf-8") as f:
                f.write(style_text(view))
            self.send(("saved: %s" % target).encode())

    server = HTTPServer(("127.0.0.1", a.port), Handler)
    url = "http://127.0.0.1:%d/" % a.port
    print("style editor: %s (Ctrl+C ends)" % url, flush=True)
    threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
