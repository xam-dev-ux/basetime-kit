// Submits the pre-signed probes (control first) via base_sendRawTransactionValidity and records
// whether each lands, in which block, and in which 200ms slot of that block.
// Question under test: is flashblock_index matched against anything at runtime
// now that Flashblocks are gone? Usage: node script/flashblock-probe-submit.mjs
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";

const RPC = "https://sepolia.base.org";
const SEQ = "https://sepolia-sequencer.base.org";
const WAIT_BLOCKS = 280; // stay inside the 60s expiry limit (300 blocks)
const signed = JSON.parse(readFileSync(".tmp/probe-signed.json", "utf8"));

const rpc = async (url, method, params) => {
  const r = await fetch(url, { method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) });
  return r.json();
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const hex = (n) => "0x" + n.toString(16);

async function probe(label, raw, fb) {
  const head = parseInt((await rpc(RPC, "eth_blockNumber", [])).result, 16);
  const maxBlock = head + WAIT_BLOCKS;
  const validity = [{ type: "block_number", params: { op: "<=", value: hex(maxBlock) } }];
  if (fb !== null) validity.push({ type: "flashblock_index", params: { op: "=", value: hex(fb) } });
  const t0 = Date.now();
  const sub = await rpc(SEQ, "base_sendRawTransactionValidity", [raw, { validity }]);
  const rec = { label, flashblockIndex: fb, submittedAtBlock: head, maxBlock, submit: sub.result ?? sub.error };
  if (sub.error) { rec.outcome = "rejected"; return rec; }
  const hash = sub.result;
  rec.hash = hash;
  for (;;) {
    const cur = parseInt((await rpc(RPC, "eth_blockNumber", [])).result, 16);
    const rc = (await rpc(RPC, "eth_getTransactionReceipt", [hash])).result;
    if (rc) {
      const bn = parseInt(rc.blockNumber, 16);
      const blk = (await rpc(RPC, "eth_getBlockByNumber", [rc.blockNumber, false])).result;
      const ms = blk.timestampMs ? Number(BigInt(blk.timestampMs)) : null;
      Object.assign(rec, { outcome: "mined", status: rc.status, block: bn, txIndex: parseInt(rc.transactionIndex, 16),
        blockTimestampMs: ms, slot: ms === null ? null : (ms % 1000) / 200,
        blocksAfterSubmit: bn - head, wallSeconds: (Date.now() - t0) / 1000 });
      return rec;
    }
    if (cur > maxBlock + 5) { rec.outcome = "not-included-before-expiry"; rec.wallSeconds = (Date.now() - t0) / 1000; return rec; }
    await sleep(250);
  }
}

const log = { startedAt: new Date().toISOString(), probes: [] };
// Control: no flashblock_index predicate. If this does not land, the pipeline
// (gas price, sequencer path) is broken and the other results mean nothing.
const k = await probe("K control, no flashblock_index", signed.K, null);
log.probes.push(k); console.log(k);
if (k.outcome !== "mined") {
  writeFileSync(".deployments/flashblock-probe.json", JSON.stringify(log, null, 2));
  console.log("control did not land: aborting, results would be meaningless");
  process.exit(1);
}
const a = await probe("A fb=1 nonce N+1", signed.A, 1);
log.probes.push(a); console.log(a);
const second = a.outcome === "mined" ? ["C fb=10 nonce N+2", signed.C] : ["B fb=10 nonce N+1", signed.B];
const b = await probe(second[0], second[1], 10);
log.probes.push(b); console.log(b);

mkdirSync(".deployments", { recursive: true });
writeFileSync(".deployments/flashblock-probe.json", JSON.stringify(log, null, 2));
console.log("wrote .deployments/flashblock-probe.json");
