"""Bind joints of a guessed hierarchy against the mesh: python check_bind.py MESH ANIM p0,p1,..."""
import sys
import numpy as np
import m2anim, m2mesh

np.set_printoptions(precision=2, suppress=True)
g, v, b = m2mesh.read(sys.argv[1])
q, t = m2anim.read(sys.argv[2])
par = [int(x) for x in sys.argv[3].split(",")]
W = np.zeros((len(par), 3))
for i, p in enumerate(par):
    W[i] = (W[p] if p >= 0 else 0) + t[0, i]
main = np.where(v["weight"][:, 0] >= v["weight"][:, 1], v["bone"][:, 0], v["bone"][:, 1])
for i in range(len(par)):
    pv = v["pos"][main == i]
    if len(pv):
        near = np.min(np.linalg.norm(pv - W[i], axis=1))
        print(f"{b[i]:22} joint {W[i]} n={len(pv):4} centre {pv.mean(0)} nearest {near:.2f}")
    else:
        print(f"{b[i]:22} joint {W[i]} no vertices")
