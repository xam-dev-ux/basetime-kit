// Follow-up to the first probe: "= 1" and "= 10" never landed while the control
// did. Which predicates DO land? Cases run until the first one mines (the nonce
// is then spent), so order goes from most to least informative. Each case waits
// up to ~20s (100 blocks); the control lands in under a second.
import { readFileSync, writeFileSync } from "node:fs";
const RPC = "https://sepolia.base.org", SEQ = "https://sepolia-sequencer.base.org";
const WAIT_BLOCKS = 100;
const { raw } = JSON.parse(readFileSync(".tmp/probe2-signed.json", "utf8"));
const rpc = async (u, method, params) => (await fetch(u, { method: "POST", headers: { "content-type": "application/json" },
  body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) })).json();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const hex = (n) => "0x" + n.toString(16);

const cases = [
  [">=", 1], ["<=", 10], ["<=", 1], ["!=", 1], [">", 0],
  ["=", 2], ["=", 3], ["=", 4], ["=", 5], ["=", 6], ["=", 9],
  [">=", 6], [">", 10], ["!=", 0], ["<", 1],
];
const results = [];
for (const [op, v] of cases) {
  const head = parseInt((await rpc(RPC, "eth_blockNumber", [])).result, 16);
  const maxBlock = head + WAIT_BLOCKS;
  const validity = [{ type: "block_number", params: { op: "<=", value: hex(maxBlock) } },
                    { type: "flashblock_index", params: { op, value: hex(v) } }];
  const t0 = Date.now();
  const sub = await rpc(SEQ, "base_sendRawTransactionValidity", [raw, { validity }]);
  const rec = { predicate: `flashblock_index ${op} ${v}`, submittedAtBlock: head };
  if (sub.error) { rec.outcome = "rejected"; rec.error = sub.error.message; }
  else {
    for (;;) {
      const cur = parseInt((await rpc(RPC, "eth_blockNumber", [])).result, 16);
      const rc = (await rpc(RPC, "eth_getTransactionReceipt", [sub.result])).result;
      if (rc) {
        const blk = (await rpc(RPC, "eth_getBlockByNumber", [rc.blockNumber, false])).result;
        const ms = Number(BigInt(blk.timestampMs));
        Object.assign(rec, { outcome: "mined", hash: sub.result, block: parseInt(rc.blockNumber, 16),
          blockTimestampMs: ms, slot: (ms % 1000) / 200, wallSeconds: (Date.now() - t0) / 1000 });
        break;
      }
      if (cur > maxBlock + 3) { rec.outcome = "not-included"; break; }
      await sleep(250);
    }
  }
  results.push(rec); console.log(rec);
  if (rec.outcome === "mined") break;
}
writeFileSync(".deployments/flashblock-probe2.json", JSON.stringify(results, null, 2));
console.log("wrote .deployments/flashblock-probe2.json");
