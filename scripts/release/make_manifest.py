#!/usr/bin/env python3
"""Gera release-manifest.<servico>.json (schema 1) a partir do docker-archive."""
import argparse
import datetime
import gzip
import hashlib
import json
import re
import tarfile

ap = argparse.ArgumentParser()
ap.add_argument("--service", required=True)
ap.add_argument("--archive", required=True)
ap.add_argument("--tag", required=True)  # imagem:versao
ap.add_argument("--version", required=True)
ap.add_argument("--commit", required=True)
ap.add_argument("--port", type=int, required=True)
ap.add_argument("--timeout", type=int, required=True)
ap.add_argument("--env", required=True)  # lista separada por virgula
ap.add_argument("--memory", required=True)
ap.add_argument("--cpus", required=True)
ap.add_argument("--pre-deploy", default="")
ap.add_argument("--out", required=True)
a = ap.parse_args()

h = hashlib.sha256()
with open(a.archive, "rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        h.update(chunk)

cfg = None
with tarfile.open(fileobj=gzip.open(a.archive), mode="r|") as tar:
    for m in tar:
        if m.name == "manifest.json":
            cfg = json.load(tar.extractfile(m))[0]["Config"]
            break
if cfg is None:
    raise SystemExit("manifest.json ausente no docker-archive")
image_id = "sha256:" + re.sub(r"^.*/", "", cfg).replace(".json", "")

m = {
    "schema": 1,
    "service": a.service,
    "repo": "RangelTech/luar_chatwoot",
    "commit": a.commit[:7],
    "version": a.version,
    "artifact": {
        "type": "docker-archive",
        "asset": a.archive.split("/")[-1],
        "sha256": h.hexdigest(),
        "image_id": image_id,
        "tag": a.tag,
    },
    "built_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "healthcheck": {"path": "/health", "expect": 200, "timeout_s": a.timeout, "port": a.port},
    "env": {"required": [x for x in a.env.split(",") if x]},
    "resources": {"memory": a.memory, "cpus": a.cpus},
}
if a.pre_deploy:
    m["pre_deploy"] = {"compose_service": a.pre_deploy}
with open(a.out, "w") as f:
    json.dump(m, f, indent=2)
print(json.dumps(m, indent=2))
