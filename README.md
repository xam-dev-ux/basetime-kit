# BaseTime Kit

Contracts for Base Sepolia that read Denim's BaseTime predeploy, measure the real block production rate from onchain samples, and convert between block counts and durations. A second contract leaves onchain evidence of each Denim capability, including a pair of timers that show the `block.number` hazard in two transactions.

## What Denim changed

Denim replaces Flashblocks with canonical blocks every 200 ms: five complete blocks per second, each with its own number, hash and state root. Base Sepolia has run Denim since 2026-10-21 at 18:00 UTC. Base mainnet is a planning target for November 2026 with no activation timestamp, and this project does not target it.

**The BaseTime predeploy** at `0x4200000000000000000000000000000000000030` exposes the sub-second part of the block time. Resolution is 200 ms, not 1 ms: the millisecond part takes only the values 0, 200, 400, 600 and 800, so a second contains five slots. `timestampMs() = 1000 * block.timestamp + timestampMillisPart()`. `block.timestamp` in the EVM remains whole seconds. On a chain where Denim has not activated, the address holds the proxy runtime with an unset implementation, so calls to it revert. `BaseTimeLib` wraps the calls in `staticcall` and falls back to whole-second behaviour.

**The hazard.** `block.number` now advances ten times faster in wall-clock time, while `block.timestamp` still advances in whole seconds. Anything written as `block.number - start >= N`, `expirationBlock = block.number + N`, vesting in blocks or governance windows in blocks elapses in one tenth of the intended time. Block-count constants in immutable contracts cannot be retuned.

## Deployed contracts (Base Sepolia, chain 84532)

| Contract | Address | Deploy block |
|---|---|---|
| BlockRateOracle | [0x87a3742424337a956e740aaD3c1045E14aD10D2F](https://sepolia.basescan.org/address/0x87a3742424337a956e740aaD3c1045E14aD10D2F#code) | 53120939 |
| DenimDemo | [0x8A98BA6C1E8eBBA26b08e56e330b4E1F7d27614C](https://sepolia.basescan.org/address/0x8A98BA6C1E8eBBA26b08e56e330b4E1F7d27614C#code) | 53120939 |

Deployed 2026-11-01 at 15:14:16 UTC (`timestampMs` 1793546056600) from `0x8F058fE6b568D97f85d517Ac441b52B95722fDDe`. Both are verified on BaseScan and Sourcify. Deploy transactions: [oracle](https://sepolia.basescan.org/tx/0x12252fac19acde0b86b42cb8c89a5e3bbc8987566ae4d2087cbad045939622cf), [demo](https://sepolia.basescan.org/tx/0x6c101bd0568370d6146f3a9b470b5c6084babb4848aa6886ca6c3a4e1ee24b5f). Neither contract holds funds or has an owner.

## Measured rate

60-second window on 2026-11-01, 15:18:22 UTC, public Sepolia RPC, blocks 53121853 to 53122152.

| Measure | Result |
|---|---|
| Blocks observed | 300 |
| Observed rate | 5.000 blocks per second |
| Gap between consecutive blocks | 299 of 299 were 200 ms |
| Block number gaps | none |
| Slot occupancy (0, 200, 400, 600, 800 ms) | 60, 60, 60, 60, 60 |
| `timestampMs` absent | 0 blocks |

An earlier 60-second run (2026-11-01, blocks 53102897 to 53103197, 301 blocks) gave the same: 5.000 blocks per second, 300 of 300 gaps at 200 ms, no skipped slot. Over these windows the variance was zero, so a 1 second window already gives 5.0. Raw data: [findings/measure-2026-11-01.json](findings/measure-2026-11-01.json).

The oracle's onchain reading agrees: two samples 26 blocks and 5.2 s apart ([sample 1](https://sepolia.basescan.org/tx/0x1ee5855b89f2fba8b0abc637916bbbe18cff139ce1d19bba1e9e8c9a88a7bb07), [sample 2](https://sepolia.basescan.org/tx/0x1a13ecff57a7e280d2940380180bf35358f8d23e909d12d8537ac28aecc7c65e)) give `blocksPerSecond() = 5000000` (5.0 at 1e6 precision). `reinterpret(302400)`, the seven-day constant at 2-second blocks, returns `(604800, 60480)`: it was written for 7 days and now covers 16.8 hours.

## The hazard, demonstrated

`DenimDemo.startTimer(30, 60)` starts two timers from the same transaction: one at `block.number + 30` and one at `block.timestamp + 60`. At 2-second blocks, 30 blocks was 60 seconds. Both fire events once observed elapsed.

| | Written for | Became elapsed | Event transaction |
|---|---|---|---|
| Start | | block 53122598, `timestampMs` 1793546388400 | [startTimer](https://sepolia.basescan.org/tx/0xe031232c92f6625dfe7f952e5905d5c8e7917cc73b1d2760fe021972c04223e2) |
| Block timer, `block.number + 30` | 60 s | **6 s** after start (block 53122628) | [BlockTimerFired](https://sepolia.basescan.org/tx/0x76652e594933dfa79ef9bd0993c1f3c74d360236b8876a780948d9b7bed44ecb), block 53122633, 7.0 s after start |
| Timestamp timer, `block.timestamp + 60` | 60 s | 60 s after start | [TimeTimerFired](https://sepolia.basescan.org/tx/0x36fc10cd0a6078cd9c2f3f49ab53338011d156c1c0f9280b006fbff9cd7ce0c9), block 53122906, 61.6 s after start |

The block-count timer was ready ten times sooner than intended. The event transactions land a little after the moment each timer became elapsed because `checkTimer` is a separate, permissionless call sent by the exercise script's polling loop.

The same run also shows the slot resolution. Five `recordSlot()` calls broadcast back to back landed in five consecutive blocks and five distinct slots ([slot1](https://sepolia.basescan.org/tx/0x0fcab2dd629183e59fe8ff99ac57eb15583fc39206768c22b81c5b315e5fab56), [slot2](https://sepolia.basescan.org/tx/0x3e3764d5a43537df12854f8af81d7ec055d429a4c90afe774e421801ba614735), [slot3](https://sepolia.basescan.org/tx/0xd5988e229eeffcf161acbd3145ac8776f6b71cb421f1c6033a05ba186f9c24b0), [slot4](https://sepolia.basescan.org/tx/0x40746777ef8d5452b4d3ae66ae161232a4c4273fe03ac1b28bc530ed7a0f7a10), [slot5](https://sepolia.basescan.org/tx/0xed6ca02ca69e5f72886fbd0244d6260268a997c7028816c8cf81fdeea2e330c8)), and `slotHistogram()` returned `1 1 1 1 1`. [`compareClocks()`](https://sepolia.basescan.org/tx/0x62239fa1150b7819e10d893919283d483de1a6725d309df11a667178ab3a5332) emitted `block.timestamp * 1000 = 1793546387000` next to `timestampMs = 1793546387600`.

Full log with all hashes, blocks and slots: [.deployments/exercise-log.json](.deployments/exercise-log.json).

## Using the library

Never call the predeploy directly from application code; on a chain before Denim it reverts.

```solidity
import {BaseTimeLib} from "./BaseTimeLib.sol";
import {BlockRateOracle} from "./BlockRateOracle.sol";

// Before: elapses in 1/10 of the intended time after Denim.
uint256 public constant LOCK_BLOCKS = 302_400; // "7 days" at 2 s per block

// After, option 1: do not use blocks at all.
uint256 unlockAt = block.timestamp + 7 days;

// After, option 2: derive the count from the observed rate.
uint256 lockBlocks = oracle.blocksFor(7 days); // 3_024_000 at 5 blocks per second

// Audit an existing constant:
(uint256 intended, uint256 actual) = oracle.reinterpret(302_400); // (604800, 60480)

// Sub-second time, with a defined answer on every chain:
uint256 ms = BaseTimeLib.timestampMs();   // block.timestamp * 1000 before Denim
uint8 slot = BaseTimeLib.slotIndex();     // 0 to 4, always 0 before Denim
```

Prefer `block.timestamp` for durations. The oracle is for the cases where a block count is unavoidable, and it is only as fresh as the last `sample()`, which anyone can call.

`BaseTimeLib` treats any millisecond part other than 0, 200, 400, 600 or 800 as the predeploy being unavailable.

## Findings

Observed on Base Sepolia on 2026-11-01. Where a finding comes from one endpoint at one moment, it is stated that way.

- **Predeploy.** The proxy holds the canonical runtime with its implementation slot (EIP-1967) pointing to `0xc0D3C0d3C0d3C0D3c0d3C0d3c0D3C0d3c0d30030`. `timestampMillisPart()` returns `uint16`, `timestampMs()` returns `uint256`, and at the same block `timestampMs() == 1000 * timestamp + timestampMillisPart()`. The ABI inferred from the docs was correct.
- **Deposit position.** The BaseTime update is `tx[1]`, sent by `0xdeaddeaddeaddeaddeaddeaddeaddeaddead0001`, right after the L1 information deposit at `tx[0]`.
- **Optional RPC fields.** `timestampMs` was present on every block sampled (over 900 blocks across three runs). `blockTimestampMs` was present on transactions and on `eth_getLogs` results sampled. Pruned or old data was not tested, so absence handling is untested here.
- **Block production.** 5.000 blocks per second, 200 ms between all consecutive blocks, no skipped slot, uniform slot occupancy.
- **`"pending"` still responds.** The migration guide says `"pending"` has no direct equivalent. On the public Sepolia RPC `eth_getBlockByNumber("pending")` and `eth_getTransactionCount(..., "pending")` still respond, and in five batched requests `pending` returned the same number, hash and `timestampMs` as `latest`. Sequential requests can differ by a block or two. This is behaviour of that endpoint at that time, not a protocol guarantee, and it looks intentional on the node side. The practical point is that an integration that does not migrate gets no error and no pre-confirmation semantics.
- **`flashblock_index` validity predicate.** A validity transaction submitted to `https://sepolia-sequencer.base.org` with a `flashblock_index` predicate is accepted and returns a hash, and was never included. The same transaction without that predicate, sent first as a control, was included in about 0.5 s. Fourteen predicates (`= 2, 3, 4, 5, 6, 9`, `>= 1`, `>= 6`, `> 0`, `!= 0`, `!= 1`, `<= 1`, `<= 10`, `> 10`), each with a 20 s window, were accepted and never included, in two runs the same day; `= 1` and `= 10` were also never included in a 57 s window. Only `= 0` and `< 1` are rejected at submission ("can never be satisfied by a pooled transaction"). Values above the documented maximum of 10 (11, 100, 65535, 2^32 and up) pass submission, so the documented 1 to 10 range is not enforced. The validity transaction docs still describe Flashblocks. This was reported to the Base node repository as an issue; whether it is intended is not established here. Data: [findings/flashblock-probe.json](findings/flashblock-probe.json), [findings/flashblock-probe2.json](findings/flashblock-probe2.json). A first attempt with too low a gas price was discarded as invalid.
- **WebSocket subscriptions.** `wss://sepolia.base.org` rejects the handshake with HTTP 405. `eth_subscribe("newFlashblocks")` and `"pendingLogs"` were therefore not tested and are unverified.
- **Toolchain.** `base-forge` v1.5.1 (built 2026-10-23, after Denim) compiles the contracts and forks Sepolia. The standard `forge` 1.7.1 was left untouched.

## Limitations

- Base Sepolia only. Base mainnet has no activation timestamp and the required node versions are not published; nothing here targets it.
- Local simulation of the predeploy is not available. The Denim docs state that locally mined Anvil blocks are not expected to produce BaseTime metadata; this was not tested here. The unit suites run against a mock etched at the predeploy address. Live behaviour is checked by the fork suite and by the scripts on Sepolia.
- Resolution is 200 ms. Nothing here provides millisecond precision.
- `timestampMs` and `blockTimestampMs` are optional RPC fields. Consumers must handle absence; this project does not exercise that case.
- The oracle's rate covers the most recent 10 samples, and a stale oracle reports a stale rate.
- The WebSocket checks above are unverified.

## Development

```
make install        # forge-std
make test           # 29 unit tests against a mock
make test-fork      # 4 integration checks against live Sepolia
make measure        # 60 s block production measurement, no keystore
make deploy-sepolia # keystore "speedrun", interactive password
make exercise       # signs 11 transactions up front, then broadcasts and logs them
```

The keystore password is typed at each prompt; no key is read from the environment or files. See `.env.example`.
