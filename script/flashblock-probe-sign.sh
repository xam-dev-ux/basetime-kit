#!/usr/bin/env bash
# Signs four zero/dust-value self-transfers with the speedrun keystore. Run it
# yourself: each base-cast call prompts for the keystore password. Nothing is
# broadcast here.
#   K: nonce N    control, submitted with NO flashblock_index predicate
#   A: nonce N+1  submitted with flashblock_index = 1
#   B: nonce N+1  submitted with flashblock_index = 10 (used if A never lands)
#   C: nonce N+2  submitted with flashblock_index = 10 (used if A lands)
# Values differ (0/0/1/1 wei) so every signed transaction has a distinct hash.
# Predicates are not part of the signed payload, so submit-time bounds stay fresh.
set -euo pipefail
RPC=https://sepolia.base.org
ME=0x8F058fE6b568D97f85d517Ac441b52B95722fDDe
OUT=.tmp/probe-signed.json
mkdir -p .tmp

N=$(base-cast nonce "$ME" --rpc-url "$RPC" 2>/dev/null | tail -1)
BASEFEE=$(base-cast base-fee --rpc-url "$RPC" 2>/dev/null | tail -1)
MAXFEE=$((BASEFEE * 6 + 1000000))
echo "current nonce: $N  base fee: $BASEFEE wei  maxFeePerGas: $MAXFEE wei"

sign() { # nonce value-wei
  base-cast mktx "$ME" --value "$2" --nonce "$1" --chain 84532 --gas-limit 21000 \
    --gas-price "$MAXFEE" --priority-gas-price 1000000 \
    --account speedrun --rpc-url "$RPC" | tail -1
}

K=$(sign "$N" 0)
A=$(sign "$((N + 1))" 0)
B=$(sign "$((N + 1))" 1)
C=$(sign "$((N + 2))" 1)
jq -n --arg n "$N" --arg K "$K" --arg A "$A" --arg B "$B" --arg C "$C" \
  '{nonce:($n|tonumber), K:$K, A:$A, B:$B, C:$C}' > "$OUT"
echo "signed 4 transactions -> $OUT (not broadcast)"
