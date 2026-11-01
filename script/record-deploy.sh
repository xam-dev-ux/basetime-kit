#!/usr/bin/env bash
# Adds transaction hashes, deploy block and block timestampMs from the broadcast
# artifact and receipts to .deployments/sepolia.json. No keys involved.
set -euo pipefail
RPC=${SEPOLIA_RPC_URL:-https://sepolia.base.org}
B=broadcast/Deploy.s.sol/84532/run-latest.json
D=.deployments/sepolia.json
[ -f "$B" ] || { echo "no broadcast artifact at $B"; exit 1; }

rpc() { curl -s -X POST "$RPC" -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}" | jq -c .result; }

ORACLE_TX=$(jq -r '[.transactions[]|select(.contractName=="BlockRateOracle")][0].hash' "$B")
DEMO_TX=$(jq -r '[.transactions[]|select(.contractName=="DenimDemo")][0].hash' "$B")
BN_HEX=$(rpc eth_getTransactionReceipt "[\"$ORACLE_TX\"]" | jq -r .blockNumber)
BLK=$(rpc eth_getBlockByNumber "[\"$BN_HEX\",false]")
DEMO_BN_HEX=$(rpc eth_getTransactionReceipt "[\"$DEMO_TX\"]" | jq -r .blockNumber)

jq --arg o "$ORACLE_TX" --arg d "$DEMO_TX" \
   --argjson ob "$((BN_HEX))" --argjson db "$((DEMO_BN_HEX))" \
   --argjson ts "$(echo "$BLK" | jq '(.timestamp|tonumber? // 0)')" \
   --argjson ms "$(echo "$BLK" | jq -r '.timestampMs' | xargs printf '%d')" \
   '. + {oracleTx:$o, demoTx:$d, oracleDeployBlock:$ob, demoDeployBlock:$db,
         oracleDeployBlockTimestampMs:$ms}' "$D" > "$D.tmp" && mv "$D.tmp" "$D"
cat "$D"
