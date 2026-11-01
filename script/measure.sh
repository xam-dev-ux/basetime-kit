#!/usr/bin/env bash
# Standalone, no keystore. Polls the latest block for 60 seconds and reports the
# observed block rate, slot distribution, gaps and any absence of timestampMs.
set -euo pipefail
RPC=${SEPOLIA_RPC_URL:-https://sepolia.base.org}
DURATION=${DURATION:-60}
mkdir -p .tmp
RPC="$RPC" DURATION="$DURATION" python3 -I - <<'PY'
import json, os, time, urllib.request
from collections import Counter
R, DUR = os.environ["RPC"], int(os.environ["DURATION"])
def rpc(m, p):
    req = urllib.request.Request(R, json.dumps({"jsonrpc":"2.0","id":1,"method":m,"params":p}).encode(),
                                 {"content-type":"application/json","user-agent":"curl/8.5"})
    return json.load(urllib.request.urlopen(req, timeout=10))["result"]
def parse(b):
    return (int(b["timestamp"],16), int(b["timestampMs"],16) if b.get("timestampMs") else None)
seen, t0 = {}, time.time()
while time.time() - t0 < DUR:
    try:
        b = rpc("eth_getBlockByNumber", ["latest", False]); seen[int(b["number"],16)] = parse(b)
    except Exception: pass
    time.sleep(0.08)
ns = sorted(seen)
for n in range(ns[0], ns[-1]+1):          # fill blocks the poll missed
    if n not in seen: seen[n] = parse(rpc("eth_getBlockByNumber", [hex(n), False]))
ns = sorted(seen)
absent = [n for n in ns if seen[n][1] is None]
ms = [seen[n][1] for n in ns if seen[n][1] is not None]
deltas = Counter(b-a for a, b in zip(ms, ms[1:]))
slots = Counter((m % 1000)//200 for m in ms)
bps = (ns[-1]-ns[0]) / ((ms[-1]-ms[0])/1000) if len(ms) > 1 else None
gaps = [(a, b) for a, b in zip(ns, ns[1:]) if b != a+1]
out = {"date": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "rpc": R, "windowSeconds": DUR,
       "firstBlock": ns[0], "lastBlock": ns[-1], "blocks": len(ns), "blocksPerSecond": bps,
       "deltaMsDistribution": {str(k): v for k, v in deltas.items()},
       "slotDistribution": {str(k): v for k, v in sorted(slots.items())},
       "blockNumberGaps": gaps, "timestampMsAbsentBlocks": absent,
       "raw": {str(n): list(seen[n]) for n in ns}}
json.dump(out, open(".tmp/measure.json", "w"))
print(f"blocks {ns[0]}..{ns[-1]} ({len(ns)}) over {DUR}s")
print(f"observed blocks/s: {bps}")
print("delta ms distribution:", dict(deltas))
print("slot distribution (0..4 = 0,200,400,600,800 ms):", dict(sorted(slots.items())))
print("block number gaps:", gaps or "none")
print("timestampMs absent on", len(absent), "blocks")
PY
