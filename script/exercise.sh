#!/usr/bin/env bash
# Exercises BlockRateOracle and DenimDemo on Base Sepolia from the speedrun keystore.
#   bash script/exercise.sh          sign, then run
#   bash script/exercise.sh sign     only sign (11 password prompts), nothing is broadcast
#   bash script/exercise.sh run      only broadcast the signed transactions and record results
# The keystore password is typed at each prompt. Transactions are signed up front so the
# five recordSlot calls can be broadcast back to back, which a prompt per call would prevent.
set -euo pipefail
RPC=${SEPOLIA_RPC_URL:-https://sepolia.base.org}
ME=0x8F058fE6b568D97f85d517Ac441b52B95722fDDe
DEP=.deployments/sepolia.json
SIGNED=.tmp/exercise-signed.json
LOG=.deployments/exercise-log.json
ORACLE=$(jq -r .oracle "$DEP"); DEMO=$(jq -r .demo "$DEP")
TIMER_BLOCKS=30   # written for 60 s at 2 s/block
TIMER_SECS=60
mkdir -p .tmp

sign_all() {
  local n basefee maxfee id
  n=$(base-cast nonce "$ME" --rpc-url "$RPC" 2>/dev/null | tail -1)
  basefee=$(base-cast base-fee --rpc-url "$RPC" 2>/dev/null | tail -1)
  maxfee=$((basefee * 6 + 1000000))
  id=$(base-cast call "$DEMO" "timerCount()(uint256)" --rpc-url "$RPC" 2>/dev/null | tail -1 | awk '{print $1}')
  echo "nonce $n, maxFeePerGas $maxfee wei, next timer id $id"
  local specs=(
    "sample1|$ORACLE|sample()|300000"
    "sample2|$ORACLE|sample()|300000"
    "slot1|$DEMO|recordSlot()|150000" "slot2|$DEMO|recordSlot()|150000" "slot3|$DEMO|recordSlot()|150000"
    "slot4|$DEMO|recordSlot()|150000" "slot5|$DEMO|recordSlot()|150000"
    "compare|$DEMO|compareClocks()|80000"
    "startTimer|$DEMO|startTimer(uint64,uint64)|300000|$TIMER_BLOCKS|$TIMER_SECS"
    "checkBlockTimer|$DEMO|checkTimer(uint256)|150000|$id"
    "checkTimeTimer|$DEMO|checkTimer(uint256)|150000|$id"
  )
  echo '{}' > "$SIGNED"
  local i=0 spec name to sig gas a1 a2 raw
  for spec in "${specs[@]}"; do
    IFS='|' read -r name to sig gas a1 a2 <<<"$spec"
    echo "signing $name (nonce $((n + i)))"
    raw=$(base-cast mktx "$to" "$sig" ${a1:+"$a1"} ${a2:+"$a2"} --nonce $((n + i)) --chain 84532 \
      --gas-limit "$gas" --gas-price "$maxfee" --priority-gas-price 1000000 \
      --account speedrun --rpc-url "$RPC" | tail -1)
    jq --arg k "$name" --arg v "$raw" '. + {($k):$v}' "$SIGNED" > "$SIGNED.t" && mv "$SIGNED.t" "$SIGNED"
    i=$((i + 1))
  done
  jq --argjson n "$n" --argjson id "$id" '. + {_nonce:$n, _timerId:$id}' "$SIGNED" > "$SIGNED.t" && mv "$SIGNED.t" "$SIGNED"
  echo "signed ${#specs[@]} transactions -> $SIGNED (not broadcast)"
}

rpc() { curl -s -X POST "$RPC" -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}" | jq -c .result; }
raw_of() { jq -r --arg k "$1" '.[$k]' "$SIGNED"; }
send() { base-cast publish "$(raw_of "$1")" --async --rpc-url "$RPC" 2>/dev/null | tail -1; }
wait_receipt() { # hash -> prints receipt json
  local r
  for _ in $(seq 1 200); do
    r=$(rpc eth_getTransactionReceipt "[\"$1\"]")
    [ "$r" != "null" ] && { echo "$r"; return; }
    sleep 0.25
  done
  echo "timeout waiting for $1" >&2; return 1
}
block_ms() { rpc eth_getBlockByNumber "[\"$1\",false]" | jq -r '.timestampMs' | xargs printf '%d'; }
record() { # name hash  -> appends tx record to LOG
  local r bn ms
  r=$(wait_receipt "$2"); bn=$(echo "$r" | jq -r .blockNumber); ms=$(block_ms "$bn")
  jq --arg name "$1" --arg h "$2" --argjson r "$r" --argjson ms "$ms" \
    '.txs += [{name:$name, hash:$h, status:$r.status, block:($r.blockNumber|tonumber? // $r.blockNumber),
               gasUsed:$r.gasUsed, blockTimestampMs:$ms, slot:(($ms % 1000)/200|floor)}]' "$LOG" > "$LOG.t" && mv "$LOG.t" "$LOG"
  echo "$1: $2 block $((bn)) ms $ms slot $(( (ms % 1000) / 200 ))"
}
call() { base-cast call "$@" --rpc-url "$RPC" 2>/dev/null; }

run_all() {
  echo "{\"oracle\":\"$ORACLE\",\"demo\":\"$DEMO\",\"startedAt\":\"$(date -u +%FT%TZ)\",\"txs\":[]}" > "$LOG"
  local h id; id=$(jq -r ._timerId "$SIGNED")

  echo "== 1. first sample";  h=$(send sample1); record sample1 "$h"
  echo "== 2. wait past minSampleGapMs, sample again"; sleep 4
  h=$(send sample2); record sample2 "$h"

  echo "== 3. blocksPerSecond"
  local bps; bps=$(call "$ORACLE" "blocksPerSecond()(uint256)" | awk '{print $1}')
  echo "blocksPerSecond (1e6 = 1/s): $bps"
  jq --arg v "$bps" '.blocksPerSecond=$v' "$LOG" > "$LOG.t" && mv "$LOG.t" "$LOG"

  echo "== 4. reinterpret(302400)"
  local re; re=$(call "$ORACLE" "reinterpret(uint256)(uint256,uint256)" 302400 | awk '{print $1}' | paste -sd,)
  echo "intended seconds, actual seconds: $re"
  jq --arg v "$re" '.reinterpret302400=$v' "$LOG" > "$LOG.t" && mv "$LOG.t" "$LOG"

  echo "== 5. recordSlot x5 back to back"
  local hs=() k
  for k in 1 2 3 4 5; do hs+=("$(send slot$k)"); done
  for k in 1 2 3 4 5; do record slot$k "${hs[$((k - 1))]}"; done
  local hist; hist=$(call "$DEMO" "slotHistogram()(uint256[5])" | tr -d '[]' | tr -s ' ,' ' ')
  echo "slotHistogram: $hist"
  local distinct; distinct=$(jq '[.txs[]|select(.name|startswith("slot"))|.slot]|unique|length' "$LOG")
  jq --arg v "$hist" --argjson d "$distinct" '.slotHistogram=$v | .distinctSlotsOfFiveCalls=$d' "$LOG" > "$LOG.t" && mv "$LOG.t" "$LOG"
  [ "$distinct" -gt 1 ] && echo "OK: calls landed in $distinct distinct slots" || echo "WARNING: all five calls landed in one slot"

  echo "== 6. compareClocks"; h=$(send compare); record compare "$h"

  echo "== 7. timers (block target $TIMER_BLOCKS blocks, time target $TIMER_SECS s)"
  h=$(send startTimer); record startTimer "$h"
  local sb sms target t0; sb=$(jq -r '.txs[]|select(.name=="startTimer")|.block' "$LOG"); sms=$(jq -r '.txs[]|select(.name=="startTimer")|.blockTimestampMs' "$LOG")
  sb=$((sb)); target=$((sb + TIMER_BLOCKS)); t0=$(date +%s)
  echo "waiting for block timer (block $target)"
  until [ "$(call "$DEMO" "isBlockTimerElapsed(uint256)(bool)" "$id")" = "true" ]; do sleep 0.5; done
  local wall_block=$(( $(date +%s) - t0 ))
  h=$(send checkBlockTimer); record checkBlockTimer "$h"
  local tms; tms=$(block_ms "$target")
  echo "block timer: written for $TIMER_SECS s, target block $target had timestampMs $tms, i.e. $(( (tms - sms) / 1000 )) s after start (wall $wall_block s)"
  echo "waiting for time timer"
  until [ "$(call "$DEMO" "isTimeTimerElapsed(uint256)(bool)" "$id")" = "true" ]; do sleep 1; done
  h=$(send checkTimeTimer); record checkTimeTimer "$h"
  local fms; fms=$(jq -r '.txs[]|select(.name=="checkTimeTimer")|.blockTimestampMs' "$LOG")
  jq --argjson sms "$sms" --argjson tms "$tms" --argjson fms "$fms" --argjson sb "$sb" --argjson tb "$target" \
     --argjson nominal "$TIMER_SECS" \
     '.timers={nominalSeconds:$nominal, startBlock:$sb, blockTarget:$tb, blockTimerElapsedAfterSeconds:(($tms-$sms)/1000),
               timeTimerFiredAfterSeconds:(($fms-$sms)/1000)}' "$LOG" > "$LOG.t" && mv "$LOG.t" "$LOG"
  echo "wrote $LOG"
}

case "${1:-all}" in
  sign) sign_all ;;
  run)  run_all ;;
  all)  sign_all; run_all ;;
  *) echo "usage: $0 [sign|run]"; exit 2 ;;
esac
