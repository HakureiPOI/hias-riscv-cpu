#!/usr/bin/env python3
"""Create controlled DUT-trace variants for P1-C-R1 negative probes."""
import argparse
import json
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--mode", required=True, choices=[
        "extra_endpoint", "extra_other", "bad_line", "priv", "last_next",
        "dirty_pc"])
    a = ap.parse_args()
    lines = [ln for ln in Path(a.src).read_text(encoding="utf-8").splitlines() if ln.strip()]
    recs = [json.loads(ln) for ln in lines]
    end_pc = recs[-1]["pc"]
    if a.mode == "extra_endpoint":
        r = json.loads(json.dumps(recs[-1]))
        r["seq"] = len(recs)
        r["token"]["gen"] = len(recs) & 0xff
        r["pc"] = end_pc
        recs.append(r)
    elif a.mode == "extra_other":
        r = json.loads(json.dumps(recs[-1]))
        r["seq"] = len(recs)
        r["token"]["gen"] = len(recs) & 0xff
        r["pc"] = (end_pc - 4) & 0xffffffff
        recs.append(r)
    elif a.mode == "bad_line":
        pass
    elif a.mode == "priv":
        recs[1]["priv"] = "S"
    elif a.mode == "last_next":
        recs[-1]["next_pc"] = (recs[-1]["next_pc"] + 4) & 0xffffffff
    elif a.mode == "dirty_pc":
        recs[0]["pc"] = (recs[0]["pc"] + 4) & 0xffffffff
    out = "\n".join(json.dumps(r, separators=(",", ":")) for r in recs)
    if a.mode == "bad_line":
        out += "\nthis is not a valid JSON record\n"
    else:
        out += "\n"
    Path(a.out).write_text(out, encoding="utf-8")


if __name__ == "__main__":
    main()
