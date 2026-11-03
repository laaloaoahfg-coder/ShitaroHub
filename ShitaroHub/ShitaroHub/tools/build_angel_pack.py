#!/usr/bin/env python3
"""Converts a skinned .glb character into a pack the skins module can load.

    python3 tools/build_angel_pack.py angel.glb front.png models/angel_v1.pack

What it does
  * splits the model by dominant bone into the 15 R15 body parts
    (head, torso halves, 3 pieces per arm, 3 pieces per leg)
  * poses the T-pose arms down (linear blend skinning) so they hang like a
    Roblox avatar's
  * turns it to face -Z, scales it to REF_HEIGHT studs, feet at y = 0
  * writes every piece as a Roblox .mesh (version 2.00, binary)
  * bakes textures (base colour factors, a colour palette, the wing gradient)
  * packs meshes + textures + a thumbnail + a JSON description into ONE file

Pack layout:  "SHP1" | u32 header length | JSON header | file blobs (in order)
"""
import io
import json
import math
import struct
import sys

import numpy as np
from PIL import Image

REF_HEIGHT = 5.0          # studs, sole to top of head
ARM_TILT_DEG = 14.0       # how far the arms hang away from the body
MAX_TEXTURE = 1024
DOUBLE_SIDED = {"Wings", "Dress", "Straps", "Hair", "Bandages"}
MESH_GROUP_OVERRIDE = {   # whole mesh goes to one body part
    "Dress": "LowerTorso", "Straps": "UpperTorso", "Wings": "UpperTorso",
    "Hair": "Head", "Torus": "Head", "Face": "Head",
}

GROUPS = [
    "LowerTorso", "UpperTorso", "Head",
    "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
]
GIDX = {g: i for i, g in enumerate(GROUPS)}

CTYPES = {5120: "<i1", 5121: "<u1", 5122: "<i2", 5123: "<u2",
          5125: "<u4", 5126: "<f4"}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_glb(path):
    data = open(path, "rb").read()
    offset, js, blob = 12, None, None
    while offset < len(data):
        length, kind = struct.unpack("<II", data[offset:offset + 8])
        chunk = data[offset + 8:offset + 8 + length]
        offset += 8 + length
        if kind == 0x4E4F534A:
            js = json.loads(chunk)
        elif kind == 0x004E4942:
            blob = chunk
    return js, blob


class Gltf:
    def __init__(self, path):
        self.js, self.blob = load_glb(path)

    def accessor(self, index):
        acc = self.js["accessors"][index]
        view = self.js["bufferViews"][acc["bufferView"]]
        dtype = np.dtype(CTYPES[acc["componentType"]])
        comps = NCOMP[acc["type"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride", 0)
        count = acc["count"]
        if stride and stride != dtype.itemsize * comps:
            raw = np.frombuffer(self.blob, dtype=np.uint8,
                                count=stride * count, offset=start)
            raw = raw.reshape(count, stride)[:, :dtype.itemsize * comps]
            out = np.ascontiguousarray(raw).view(dtype).reshape(count, comps)
        else:
            out = np.frombuffer(self.blob, dtype=dtype, count=count * comps,
                                offset=start).reshape(count, comps)
        out = out.astype(np.float64) if dtype.kind == "f" else out.copy()
        if acc.get("normalized"):
            out = out.astype(np.float64) / float(np.iinfo(dtype).max)
        return out

    def image(self, index):
        view = self.js["bufferViews"][self.js["images"][index]["bufferView"]]
        start = view.get("byteOffset", 0)
        raw = self.blob[start:start + view["byteLength"]]
        return Image.open(io.BytesIO(raw)).convert("RGBA")


def to_srgb(linear):
    linear = np.clip(linear, 0.0, 1.0)
    return np.where(linear <= 0.0031308, linear * 12.92,
                    1.055 * np.power(linear, 1 / 2.4) - 0.055)


def to_linear(srgb):
    srgb = np.clip(srgb, 0.0, 1.0)
    return np.where(srgb <= 0.04045, srgb / 12.92,
                    np.power((srgb + 0.055) / 1.055, 2.4))


def group_of_joint(name):
    side = "Left" if "_L_" in name else "Right" if "_R_" in name else ""
    if name.startswith("Wing_") or "Bust" in name or "Shoulder" in name:
        return "UpperTorso"
    if "Sec_Hair" in name or "FaceEye" in name or "C_Neck" in name \
            or "C_Head" in name:
        return "Head"
    if "C_Hips" in name or name == "neutral_bone":
        return "LowerTorso"
    if "C_Spine" in name or "C_Chest" in name or "C_UpperChest" in name:
        return "UpperTorso"
    if "UpperArm" in name:
        return side + "UpperArm"
    if "LowerArm" in name or "Elbow" in name:
        return side + "LowerArm"
    if "Hand" in name or any(k in name for k in
                             ("Index", "Little", "Middle", "Ring", "Thumb")):
        return side + "Hand"
    if "UpperLeg" in name:
        return side + "UpperLeg"
    if "LowerLeg" in name:
        return side + "LowerLeg"
    if "Foot" in name or "Toe" in name:
        return side + "Foot"
    raise SystemExit("unmapped joint: " + name)


def rotation_between(a, b):
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    axis = np.cross(a, b)
    s = np.linalg.norm(axis)
    c = float(np.dot(a, b))
    if s < 1e-9:
        return np.eye(3)
    axis = axis / s
    k = np.array([[0, -axis[2], axis[1]],
                  [axis[2], 0, -axis[0]],
                  [-axis[1], axis[0], 0]])
    return np.eye(3) + s * k + (1 - c) * (k @ k)


def mesh_v2(positions, normals, uvs, faces):
    out = bytearray(b"version 2.00\n")
    out += struct.pack("<HBBII", 12, 40, 12, len(positions), len(faces))
    vert = np.zeros(len(positions), dtype=[
        ("p", "<f4", 3), ("n", "<f4", 3), ("uv", "<f4", 2),
        ("t", "i1", 4), ("c", "u1", 4)])
    vert["p"] = positions
    vert["n"] = normals
    vert["uv"] = uvs
    vert["t"] = (0, 0, 127, 127)
    vert["c"] = (255, 255, 255, 255)
    assert vert.dtype.itemsize == 40
    out += vert.tobytes()
    out += np.ascontiguousarray(faces, dtype="<u4").tobytes()
    return bytes(out)


def png_bytes(image):
    buffer = io.BytesIO()
    image.save(buffer, "PNG", optimize=True)
    return buffer.getvalue()


def main(glb_path, thumb_path, out_path):
    g = Gltf(glb_path)
    js = g.js
    skin = js["skins"][0]
    nodes = js["nodes"]
    joints = skin["joints"]

    ibm = g.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4)
    ibm = ibm.transpose(0, 2, 1)
    head_pos = {nodes[j]["name"]: np.linalg.inv(ibm[k])[:3, 3]
                for k, j in enumerate(joints)}
    joint_group = np.array([GIDX[group_of_joint(nodes[j]["name"])]
                            for j in joints])

    # --- reading the primitives happens below; arms are posed afterwards ------
    tilt = math.radians(ARM_TILT_DEG)

    # --- read every primitive -------------------------------------------------
    prims = []
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            a = prim["attributes"]
            pos = g.accessor(a["POSITION"])
            prims.append({
                "name": mesh["name"].split(".")[0],
                "mat": prim["material"],
                "pos": pos,
                "nor": g.accessor(a["NORMAL"]),
                "uv": g.accessor(a["TEXCOORD_0"]) if "TEXCOORD_0" in a else None,
                "col": g.accessor(a["COLOR_0"])[:, :3] if "COLOR_0" in a else None,
                "jt": g.accessor(a["JOINTS_0"]).astype(int),
                "wt": g.accessor(a["WEIGHTS_0"]),
                "idx": g.accessor(prim["indices"]).reshape(-1, 3).astype(np.int64),
            })

    # --- pose the T-pose mesh: arms hang down (linear blend skinning) -------------
    # The glb mesh is a T-pose while its skeleton is stored in an A-pose, so the
    # arm direction is measured on the mesh itself (centroid of the hand verts).
    names = [nodes[j]["name"] for j in joints]
    pose = np.tile(np.eye(4), (len(joints), 1, 1))
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        key = "J_Bip_%s_" % side[0]
        pivot = head_pos[key + "UpperArm"]
        hand_idx = names.index(key + "Hand")
        pts = []
        for p in prims:
            dom = p["jt"][np.arange(len(p["pos"])), p["wt"].argmax(axis=1)]
            pts.append(p["pos"][dom == hand_idx])
        direction = np.concatenate(pts).mean(axis=0) - pivot
        target = np.array([sign * math.sin(tilt), -math.cos(tilt), 0.0])
        rot = rotation_between(direction, target)
        matrix = np.eye(4)
        matrix[:3, :3] = rot
        matrix[:3, 3] = pivot - rot @ pivot
        for k, name in enumerate(names):
            if group_of_joint(name) in (side + "UpperArm", side + "LowerArm",
                                        side + "Hand") \
                    or name == "J_Aim_%s_Shoulder" % side[0]:
                pose[k] = matrix
        print("%s arm: mesh points %.0f deg from vertical -> %.0f deg" % (
            side, math.degrees(math.atan2(abs(direction[0]), -direction[1])),
            ARM_TILT_DEG))

    for p in prims:
        pos_h = np.c_[p["pos"], np.ones(len(p["pos"]))]
        weights = p["wt"] / p["wt"].sum(axis=1, keepdims=True)
        new_pos = np.zeros_like(p["pos"])
        new_nor = np.zeros_like(p["nor"])
        for k in range(4):
            m = pose[p["jt"][:, k]]
            new_pos += weights[:, k:k + 1] * np.einsum("nij,nj->ni", m, pos_h)[:, :3]
            new_nor += weights[:, k:k + 1] * np.einsum("nij,nj->ni", m[:, :3, :3], p["nor"])
        length = np.linalg.norm(new_nor, axis=1, keepdims=True)
        p["pos"] = new_pos
        p["nor"] = new_nor / np.where(length == 0, 1, length)

    # --- model frame: feet at y=0, pelvis centred, scaled to REF_HEIGHT ---------
    bottom = min(p["pos"][:, 1].min() for p in prims)
    head_vertices = []
    for p in prims:
        score = np.zeros((len(p["pos"]), len(GROUPS)))
        for k in range(4):
            np.add.at(score, (np.arange(len(p["pos"])), joint_group[p["jt"][:, k]]),
                      p["wt"][:, k])
        p["score"] = score
        if p["name"] != "Torus":
            tops = score[:, GIDX["Head"]] > 0.5
            if tops.any():
                head_vertices.append(p["pos"][tops, 1].max())
    top = max(head_vertices)
    height = top - bottom
    scale = REF_HEIGHT / height
    origin = np.array([head_pos["J_Bip_C_Hips"][0], bottom,
                       head_pos["J_Bip_C_Hips"][2]])
    print("model height %.3f m -> %.2f studs (x%.3f)" % (height, REF_HEIGHT, scale))

    def transform(points, normals, group):
        points = (points - origin) * scale
        flip = np.array([-1.0, 1.0, -1.0])      # glTF faces +Z, Roblox -Z
        return points * flip, normals * flip

    # --- textures ---------------------------------------------------------------
    files = {}
    palette = []                                   # sRGB tuples

    def palette_uv(rgb):
        rgb = tuple(int(round(c * 255)) for c in rgb)
        if rgb not in palette:
            palette.append(rgb)
        return palette.index(rgb)

    def material_texture(mat_index):
        mat = js["materials"][mat_index]
        pbr = mat.get("pbrMetallicRoughness", {})
        tex = pbr.get("baseColorTexture")
        factor = np.array(pbr.get("baseColorFactor", [1, 1, 1, 1]))[:3]
        if not tex:
            return None, factor
        source = js["textures"][tex["index"]]["source"]
        name = "t_%s.png" % js["images"][source].get("name", source).lower()
        if name not in files:
            image = g.image(source)
            if max(image.size) > MAX_TEXTURE:
                ratio = MAX_TEXTURE / max(image.size)
                image = image.resize((round(image.width * ratio),
                                      round(image.height * ratio)),
                                     Image.LANCZOS)
            arr = np.asarray(image).astype(np.float64) / 255.0
            if not np.allclose(factor, 1.0):
                lin = to_linear(arr[..., :3]) * factor
                arr[..., :3] = to_srgb(lin)
            image = Image.fromarray(np.round(arr * 255).astype(np.uint8), "RGBA")
            files[name] = png_bytes(image)
        return name, factor

    # --- split into pieces ---------------------------------------------------------
    pieces = {}          # (group, key) -> list of chunks
    wing_colors = []

    for p in prims:
        face_score = (p["score"][p["idx"][:, 0]] + p["score"][p["idx"][:, 1]]
                      + p["score"][p["idx"][:, 2]])
        if p["name"] in MESH_GROUP_OVERRIDE:
            face_group = np.full(len(p["idx"]), GIDX[MESH_GROUP_OVERRIDE[p["name"]]])
        else:
            face_group = face_score.argmax(axis=1)

        mat_name = js["materials"][p["mat"]]["name"]
        texture, factor = material_texture(p["mat"])
        if texture:
            key = texture
        elif p["col"] is not None:
            key = "wing"
        elif mat_name == "HaloGlow":
            key = "halo"
        else:
            key = "solid"

        for gi in np.unique(face_group):
            group = GROUPS[gi]
            faces = p["idx"][face_group == gi]
            used, inverse = np.unique(faces.ravel(), return_inverse=True)
            local_faces = inverse.reshape(-1, 3)
            pos, nor = transform(p["pos"][used], p["nor"][used], group)
            chunk = {"pos": pos, "nor": nor, "faces": local_faces,
                     "double": p["name"] in DOUBLE_SIDED}
            if key.endswith(".png"):
                chunk["uv"] = p["uv"][used]
            elif key == "wing":
                chunk["color"] = to_srgb(p["col"][used])
                wing_colors.append(chunk["color"])
            else:
                cell = palette_uv(to_srgb(factor))
                chunk["uv"] = np.full((len(used), 2), cell, dtype=np.float64)
            pieces.setdefault((group, key), []).append(chunk)

    # --- palette + wing gradient textures -----------------------------------------
    cell = 16
    strip = Image.new("RGBA", (cell * max(len(palette), 1), cell))
    for i, rgb in enumerate(palette):
        strip.paste(rgb + (255,), (i * cell, 0, (i + 1) * cell, cell))
    files["t_palette.png"] = png_bytes(strip)
    count = max(len(palette), 1)

    colors = np.concatenate(wing_colors)
    centered = colors - colors.mean(axis=0)
    axis = np.linalg.svd(centered, full_matrices=False)[2][0]
    t_all = centered @ axis
    t_min, t_max = t_all.min(), t_all.max()
    bins = np.clip(((t_all - t_min) / (t_max - t_min) * 255).astype(int), 0, 255)
    lut = np.zeros((256, 3))
    seen = np.zeros(256, dtype=bool)
    for b in range(256):
        m = bins == b
        if m.any():
            lut[b] = colors[m].mean(axis=0)
            seen[b] = True
    xs = np.arange(256)
    for c in range(3):
        lut[:, c] = np.interp(xs, xs[seen], lut[seen, c])
    gradient = np.repeat(np.round(lut * 255).astype(np.uint8)[None], 8, axis=0)
    files["t_wing.png"] = png_bytes(Image.fromarray(gradient, "RGB"))

    # --- write meshes ------------------------------------------------------------
    description = []
    for (group, key), chunks in sorted(pieces.items()):
        positions, normals, uvs, faces, base = [], [], [], [], 0
        for chunk in chunks:
            if key == "wing":
                u = (chunk["color"] - colors.mean(axis=0)) @ axis
                u = np.clip((u - t_min) / (t_max - t_min), 0, 1) * (255 / 256) + 0.5 / 256
                uv = np.stack([u, np.full(len(u), 0.5)], axis=1)
            elif not key.endswith(".png"):
                u = (chunk["uv"][:, 0] + 0.5) / count
                uv = np.stack([u, np.full(len(u), 0.5)], axis=1)
            else:
                uv = chunk["uv"]
            n = len(chunk["pos"])
            positions.append(chunk["pos"])
            normals.append(chunk["nor"])
            uvs.append(uv)
            faces.append(chunk["faces"] + base)
            base += n
            if chunk["double"]:
                positions.append(chunk["pos"])
                normals.append(-chunk["nor"])
                uvs.append(uv)
                faces.append(chunk["faces"][:, ::-1] + base)
                base += n
        mesh_name = "m_%s_%s.mesh" % (group, key.replace(".png", "").replace("t_", ""))
        files[mesh_name] = mesh_v2(np.concatenate(positions),
                                   np.concatenate(normals),
                                   np.concatenate(uvs),
                                   np.concatenate(faces))
        texture = "t_palette.png" if key in ("solid", "halo") else (
            "t_wing.png" if key == "wing" else key)
        description.append({"group": group, "mesh": mesh_name,
                            "texture": texture, "neon": key == "halo"})
        print("  %-14s %-22s v=%6d f=%6d" % (
            group, key, base, sum(len(f) for f in faces)))

    # --- thumbnail -----------------------------------------------------------------
    thumb = Image.open(thumb_path).convert("RGBA")
    thumb.thumbnail((240, 330), Image.LANCZOS)
    files["thumb.png"] = png_bytes(thumb)

    # --- pack ----------------------------------------------------------------------
    header = json.dumps({
        "version": 1, "ref_height": REF_HEIGHT, "pieces": description,
        "files": [{"name": n, "size": len(b)} for n, b in files.items()],
    }).encode()
    with open(out_path, "wb") as fh:
        fh.write(b"SHP1" + struct.pack("<I", len(header)) + header)
        for blob in files.values():
            fh.write(blob)
    total = sum(len(b) for b in files.values())
    print("pieces %d, files %d, pack %.2f MB" % (
        len(description), len(files), (total + len(header)) / 1e6))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
