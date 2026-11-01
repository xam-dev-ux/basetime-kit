#!/usr/bin/env bash
# Signs ONE self-transfer at the current nonce. One password prompt. Not broadcast.
# The same signed transaction is reused for every predicate in probe2-submit,
# one at a time, since predicates travel outside the signed payload.
set -euo pipefail
RPC=https://sepolia.base.org
ME=0x8F058fE6b568D97f85d517Ac441b52B95722fDDe
mkdir -p .tmp
N=$(base-cast nonce "$ME" --rpc-url "$RPC" 2>/dev/null | tail -1)
BASEFEE=$(base-cast base-fee --rpc-url "$RPC" 2>/dev/null | tail -1)
MAXFEE=$((BASEFEE * 6 + 1000000))
echo "nonce: $N  maxFeePerGas: $MAXFEE wei"
RAW=$(base-cast mktx "$ME" --value 0 --nonce "$N" --chain 84532 --gas-limit 21000 \
  --gas-price "$MAXFEE" --priority-gas-price 1000000 \
  --account speedrun --rpc-url "$RPC" | tail -1)
jq -n --arg n "$N" --arg raw "$RAW" '{nonce:($n|tonumber), raw:$raw}' > .tmp/probe2-signed.json
echo "signed 1 transaction -> .tmp/probe2-signed.json (not broadcast)"
