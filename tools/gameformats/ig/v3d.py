"""Imperial Glory V3D reader (reverse-engineered, test use only) + glTF export.

Chunk: u16 tag, u16 0, u32 size (incl. 8-byte header). Data is not aligned.
A file holds one or more objects (cavalry: horse + rider, artillery: gun parts).
Mesh file, per object:
  0x2000 object header: u16-prefixed name and parent name, then three 4x4 matrices;
    the second places the object (positions are in object space; identity for soldiers)
    0x2100 array: u32 kind (0x100 = uv), u32 stride (8), u32 count, count * (u, v)
    0x2300 indices: u32 2, u32 count, count * u16
    0x2400 submeshes: u32 n, then (vstart, vcount, istart, tris, ...)
  0x7000 frame: bbox 6f, sphere 4f, then
    0x2100 array: u32 kind (2 = positions), u32 stride (12), u32 count, count * (x, y, z)
Materials: 0x1000 > 0x1100 > 0x1110 (name, colours, texture path).
Animation file, per object: 0x2000 header, then per frame 104 bytes
  (4x4 matrix M, bbox, sphere) and a 0x2100 positions array. Objects follow each other.
  Stored positions are (pose position) @ M, row vectors; M is identity for soldiers and
  horses, rigid parts (cannon wheels, barrel) use it. Static parts have a single frame.
Y is up, units are centimetres.

python v3d.py MESH.V3D TEX1[,TEX2...] OUT.gltf [ANIM.V3D ...]
  TEXn = texture of object n (in file order); missing ones repeat the last.
"""
import base64, json, os, re, struct, sys
import numpy as np


def chunks(d, tag):
    """All offsets where a chunk with this tag (and a sane size) starts."""
    pat = struct.pack("<HH", tag, 0)
    o = d.find(pat)
    while o >= 0:
        size = struct.unpack_from("<I", d, o + 4)[0]
        if 8 <= size <= len(d) - o:
            yield o, size
        o = d.find(pat, o + 1)


def arrays(d, kind, stride):
    for o, size in chunks(d, 0x2100):
        k, s, n = struct.unpack_from("<3I", d, o + 8)
        if k == kind and s == stride and size == 20 + n * stride:
            yield o, np.frombuffer(d, "<f4", n * stride // 4, o + 20).reshape(n, stride // 4)


def read_materials(d):
    """Texture file name of each material (0x1110 chunks, in order); None if it has none."""
    mats = []
    for o, size in chunks(d, 0x1110):
        names = re.findall(rb"([\w .#-]+\.(?:tga|dds))\0", d[o:o + size], re.I)
        mats.append(names[-1].decode("latin1") if names else None)
    return mats


def object_headers(d):
    """(name, parent, [M0, M1, M2]) of every object chunk (0x2000 holding geometry), in order.
    Header: ... u16 len + name, u16 len + parent name, three 4x4 matrices (row vectors).
    M1 places the object in the model; vertex positions are in object space."""
    out = []
    for o, size in chunks(d, 0x2000):
        if size < 300:
            continue
        i = o + 8
        while i < o + 64 and not (2 < struct.unpack_from("<H", d, i)[0] < 64 and d[i + 2:i + 3].isalpha()):
            i += 1
        if i >= o + 64:
            continue
        strs = []
        for _ in range(2):
            n = struct.unpack_from("<H", d, i)[0]
            strs.append(d[i + 2:i + 2 + n].split(b"\0")[0].decode("latin1"))
            i += 2 + n
        mats = np.frombuffer(d, "<f4", 48, i).reshape(3, 4, 4).astype(np.float64)
        out.append((strs[0], strs[1], mats))
    return out


def read_mesh(path):
    """(objects, materials); object = dict(uv, idx, pos, subs=[(first_tri, tris, material)])."""
    d = open(path, "rb").read()
    uvs = [a for _, a in arrays(d, 0x100, 8)]
    pos = [a for _, a in arrays(d, 2, 12)]
    idx, subs = [], []
    for o, size in chunks(d, 0x2300):
        two, n = struct.unpack_from("<2I", d, o + 8)
        if two == 2 and size == 16 + n * 2:
            idx.append(np.frombuffer(d, "<u2", n, o + 16).reshape(-1, 3))
    for o, size in chunks(d, 0x2400):
        n = struct.unpack_from("<I", d, o + 8)[0]
        if size == 12 + 20 * n:
            # per submesh: vstart, vcount, first index, triangle count, material
            subs.append([(s[2] // 3, s[3], s[4]) for s in
                         (struct.unpack_from("<5I", d, o + 12 + 20 * i) for i in range(n))])
    assert len(uvs) == len(pos) == len(idx) == len(subs), (len(uvs), len(pos), len(idx), len(subs))
    heads = object_headers(d)
    assert len(heads) == len(uvs), (len(heads), len(uvs))
    objs = [dict(uv=u, idx=i, pos=p, subs=s, name=h[0], parent=h[1], mats=h[2])
            for u, i, p, s, h in zip(uvs, idx, pos, subs, heads)]
    for ob in objs:
        assert len(ob["uv"]) == len(ob["pos"]) and ob["idx"].max() < len(ob["pos"])
        assert sum(t for _, t, _ in ob["subs"]) == len(ob["idx"])
    return objs, read_materials(d)


def read_anim(path, objs):
    """Per object: list of (matrix, positions)."""
    d = open(path, "rb").read()
    marks = sorted(o for o, _ in chunks(d, 0x2000))
    groups = {}
    for o, a in arrays(d, 2, 12):
        m = max((x for x in marks if x < o), default=-1)
        mat = np.frombuffer(d, "<f4", 16, o - 104).reshape(4, 4).astype(np.float64)
        # positions are stored multiplied by the frame matrix (row vectors): undo it
        a = (np.c_[a, np.ones(len(a))] @ np.linalg.inv(mat))[:, :3].astype("<f4")
        groups.setdefault(m, []).append((mat, a))
    out = [groups[k] for k in sorted(groups)]
    if len(out) != len(objs):  # no usable markers: split evenly
        flat = [f for g in out for f in g]
        n = len(flat) // len(objs)
        out = [flat[i * n:(i + 1) * n] for i in range(len(objs))]
    for ob, fr in zip(objs, out):
        assert all(len(p) == len(ob["pos"]) for _, p in fr), path
    return out


def write_gltf(out, objs, tex_pngs, anims, scale=0.01, fps=15):
    """objs[k]["prims"] = [(triangle array, material index)]."""
    bin_ = bytearray()
    views, accs = [], []

    def add(arr, target=None, minmax=False):
        arr = np.ascontiguousarray(arr)
        while len(bin_) % 4:
            bin_.append(0)
        views.append({"buffer": 0, "byteOffset": len(bin_), "byteLength": arr.nbytes,
                      **({"target": target} if target else {})})
        bin_.extend(arr.tobytes())
        comp = {np.dtype("<f4"): 5126, np.dtype("<u2"): 5123}[arr.dtype]
        typ = {1: "SCALAR", 2: "VEC2", 3: "VEC3"}[1 if arr.ndim == 1 else arr.shape[1]]
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": len(arr), "type": typ}
        if minmax:
            acc["min"] = arr.min(0).tolist() if arr.ndim > 1 else [float(arr.min())]
            acc["max"] = arr.max(0).tolist() if arr.ndim > 1 else [float(arr.max())]
        accs.append(acc)
        return len(accs) - 1

    meshes, nodes, samplers_by_anim = [], [], [[] for _ in anims]
    for k, ob in enumerate(objs):
        base = (ob["pos"] * scale).astype("<f4")
        attrs = {"POSITION": add(base, 34962, True), "TEXCOORD_0": add(ob["uv"].astype("<f4"), 34962)}
        prims = [{"attributes": attrs, "indices": add(tris.reshape(-1).astype("<u2"), 34963),
                  "material": mat} for tris, mat in ob["prims"]]
        prim = {"targets": []}
        names, ranges = [], []
        for name, per_obj in anims:
            first = len(prim["targets"])
            for _, p in per_obj[k]:
                prim["targets"].append({"POSITION": add((p * scale - base).astype("<f4"), None, True)})
            names += [f"{name}_{i}" for i in range(len(per_obj[k]))]
            ranges.append((first, len(per_obj[k])))
        mesh = {"name": f"obj{k}", "primitives": prims}
        total = len(prim["targets"])
        if total:
            for p in prims:
                p["targets"] = prim["targets"]
            mesh["weights"] = [0.0] * total
            mesh["extras"] = {"targetNames": names}
        for a, (first, n) in enumerate(ranges):
            if not n:
                continue
            t = np.arange(n, dtype="<f4") / fps
            w = np.zeros((n, total), "<f4")
            w[np.arange(n), first + np.arange(n)] = 1
            samplers_by_anim[a].append((k, add(t, None, True), add(w.reshape(-1), None)))
        meshes.append(mesh)
        nodes.append({"name": f"obj{k}", "mesh": k})
    gl_anims = []
    for (name, _), smp in zip(anims, samplers_by_anim):
        if smp:
            gl_anims.append({"name": name,
                             "samplers": [{"input": i, "output": o, "interpolation": "LINEAR"} for _, i, o in smp],
                             "channels": [{"sampler": s, "target": {"node": k, "path": "weights"}}
                                          for s, (k, _, _) in enumerate(smp)]})
    images = []
    for p in tex_pngs:
        with open(p, "rb") as f:
            images.append({"uri": "data:image/png;base64," + base64.b64encode(f.read()).decode()})
    g = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}],
         "nodes": nodes, "meshes": meshes,
         "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": i}, "metallicFactor": 0},
                        "doubleSided": True} for i in range(len(images))],
         "textures": [{"source": i, "sampler": 0} for i in range(len(images))],
         "samplers": [{"magFilter": 9729, "minFilter": 9729}],
         "images": images,
         "buffers": [{"byteLength": len(bin_),
                      "uri": "data:application/octet-stream;base64," + base64.b64encode(bin_).decode()}],
         "bufferViews": views, "accessors": accs}
    if gl_anims:
        g["animations"] = gl_anims
    json.dump(g, open(out, "w"))


def find_texture(folder, name):
    base = os.path.splitext(name)[0]
    for ext in (".dds", ".tga", ".DDS", ".TGA"):
        if os.path.exists(os.path.join(folder, base + ext)):
            return os.path.join(folder, base + ext)
    return None


if __name__ == "__main__":
    from PIL import Image
    mesh, texs, out = sys.argv[1:4]
    objs, mats = read_mesh(mesh)
    print("materials", mats)
    files = []  # texture file per glTF material
    if texs == "auto":  # materials' own textures, found next to the mesh; shadow quads dropped
        files = [find_texture(os.path.dirname(mesh), m) if m else None for m in mats]
        for ob in objs:
            ob["prims"] = [(ob["idx"][f:f + n], m) for f, n, m in ob["subs"]
                           if "sombra" not in (mats[m] or "").lower()]
    else:  # one texture per object (cavalry: horse, rider), the last one repeats
        files = texs.split(",")
        for k, ob in enumerate(objs):
            ob["prims"] = [(ob["idx"], min(k, len(files) - 1))]
    for k, ob in enumerate(objs):
        print(f"obj{k}: verts {len(ob['pos'])} tris {len(ob['idx'])} materials {[m for _, m in ob['prims']]}")
    pngs = []
    for k, t in enumerate(files):
        png = os.path.splitext(out)[0] + f"_tex{k}.png"
        if t:
            Image.open(t).save(png)
        else:
            Image.new("RGB", (4, 4), "magenta").save(png)
        pngs.append(png)
    anims = []
    for a in sys.argv[4:]:
        per_obj = read_anim(a, objs)
        ident = all(np.allclose(m, np.eye(4)) for fr in per_obj for m, _ in fr)
        print(os.path.basename(a), "frames", [len(f) for f in per_obj], "" if ident else "(non-identity matrices)")
        anims.append((os.path.splitext(os.path.basename(a))[0], per_obj))
    def place(p, m):
        return (np.c_[p, np.ones(len(p))] @ m)[:, :3].astype("<f4")

    for k, ob in enumerate(objs):  # object space -> model space
        m1 = ob["mats"][1]
        print(f"obj{k} {ob['name']} <- {ob['parent']}", "" if np.allclose(m1, np.eye(4)) else "placed")
        ob["pos"] = place(ob["pos"], m1)
        for _, per_obj in anims:
            per_obj[k] = [(m, place(p, m1)) for m, p in per_obj[k]]
    keep = [k for k, ob in enumerate(objs) if ob["prims"]]  # objects left with no drawn submesh go
    objs = [objs[k] for k in keep]
    anims = [(n, [per_obj[k] for k in keep]) for n, per_obj in anims]
    write_gltf(out, objs, pngs, anims)
    print("wrote", out)
