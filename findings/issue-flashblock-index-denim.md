# Title
Validity transactions with a `flashblock_index` predicate are accepted but never included on Base Sepolia after Denim

# Body

## Summary

On Base Sepolia (Denim active), `base_sendRawTransactionValidity` accepts a
`flashblock_index` predicate and returns a transaction hash, but a transaction
carrying that predicate is never included. The same transaction without the
predicate is included in under a second. The validity docs still describe
`flashblock_index` as a value from 1 to 10 within a Flashblock, and do not
mention Denim.

I would like to understand whether this is intended, so the docs can say so.

## Environment

- Network: Base Sepolia (84532), endpoint `https://sepolia-sequencer.base.org`
- Date: 2026-11-01
- Tx: EIP-1559 self-transfer, nonce-sequential, maxFeePerGas = 6 x base fee + 1 mwei

## Observations

1. Control. Submitted with only a `block_number <= head + 100` predicate: included
   in block 53108563 (about 0.5 s after submission).
2. `flashblock_index = 1` and `= 10`, with the same `block_number` bound: accepted,
   hash returned, not included before the bound expired (about 57 s each; the
   account nonce did not advance).
3. A follow-up with one signed transaction and 14 predicates, each given a
   20 s window and none included:
   `= 2, 3, 4, 5, 6, 9`, `>= 1`, `>= 6`, `> 0`, `!= 0`, `!= 1`, `<= 1`, `<= 10`, `> 10`.
   `>= 1`, `> 0` and `!= 0` would hold for any index of 1 or more.
   The 14-predicate run was repeated later the same day with the same result
   (the attached `flashblock-probe2.json` is the second run).
4. Rejected at submission, as expected from `validity.rs`: `= 0` and `< 1`
   ("flashblock-index predicate at index 1 can never be satisfied by a pooled transaction").
5. Values far above 10 (11, 100, 65535, 2^32, 0xffffffffffffffff, with `=`, `>=`, `<=`)
   all pass submission. The 1 to 10 range in the docs is not enforced.

Raw data: `flashblock-probe.json` and `flashblock-probe2.json` (attached).

## Reading of the code

`crates/execution/txpool/src/validity.rs` evaluates `FlashblockIndex` against
`context.flashblock_index`, and only starts evaluating pooled transactions at
flashblock index 1 (`FIRST_POOL_FLASHBLOCK_INDEX`). If native 200 ms blocks never
produce a pooled-transaction evaluation at index >= 1, this predicate would never
hold, which matches what I see. I have not verified that; it is an inference.

## Questions

1. Is a `flashblock_index` predicate expected to match anything after Denim?
2. If not, should submission reject it, instead of returning a hash for a
   transaction that cannot be included?
3. Should the validity pages (overview, predicates and safety, RPC reference,
   troubleshooting) be updated? They still refer to "the same Flashblock" and to
   indices 1 to 10.

## Related docs note (no bug)

The Denim migration guide says `"pending"` has no direct equivalent. On Base
Sepolia `eth_getBlockByNumber("pending")` and `eth_getTransactionCount(..., "pending")`
still respond, and in five batched requests `pending` returned the same number,
hash and `timestampMs` as `latest`. This looks intentional (#5287), but an
integration that does not migrate gets no error. A sentence in the guide would help.

## Proposal, and a request to be assigned

I am happy to work on this once you tell me which behaviour is intended. Depending
on the answer, I could send one or both of:

- A change in `crates/execution/txpool/src/validity.rs` so that submission is
  consistent with the intended behaviour. For example, rejecting a
  `flashblock_index` predicate after Denim with a clear error, or enforcing the
  documented 1 to 10 range if the predicate is meant to stay.
- A docs update for the validity pages and the Denim migration guide, if you can
  point me to where their source lives (I could not find a public docs repository).

Per CONTRIBUTING, I will not open a pull request until this issue is assigned to
me. Could you assign it to me if this is a change you would accept?
