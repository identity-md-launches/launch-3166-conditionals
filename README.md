# CONDITIONALS (CONDITION)

A fixed-supply ERC-20 implemented by `src/ConditionToken.sol:ConditionToken`.

| Parameter | Value |
| --- | --- |
| Name | `CONDITIONALS` |
| Symbol | `CONDITION` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None |
| Initial recipient | The deploying account, `msg.sender` |
| Post-deployment settings | None |

The constructor mints the entire supply once and emits the standard
`Transfer(address(0), deployer, supply)` event. No public mint or burn function,
owner, pause, blacklist, tax, transfer limit, proxy, or upgrade mechanism exists.
The token's name does not imply any additional conditional transfer rules.

ERC-20 transfers move the exact requested amount and return `true`; invalid
operations revert using OpenZeppelin's ERC-6093 custom errors. Zero-value transfers
are supported, including from empty accounts. Transfers to the zero address and
approvals to the zero spender are rejected. Self-transfers preserve balances.
`transferFrom` requires approval even when the caller is the holder; finite
allowances are consumed, while `type(uint256).max` is treated as unlimited.
`approve` replaces the current allowance and emits `Approval`. OpenZeppelin v5
does not emit `Approval` when `transferFrom` spends an allowance; integrations
should query `allowance` for its current value.

## Build and check

Foundry must be installed, with Solidity `0.8.26` available to it. Dependencies
are vendored as ordinary files under `lib/`; no network, submodules, environment
variables, FFI, or filesystem cheatcode permissions are required for the tests.
The verifier supplies the pinned Solidity compiler for offline builds.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x8e747cd1abaf641a07995a3ff008bd24269dc17ebd7029b58b5635f7dd54076d forge test
forge fmt --check
```

The configuration uses the Paris EVM target for conservative opcode compatibility,
the optimizer with 200 runs, and `bytecode_hash = "none"`. Unit and fuzz tests
cover metadata, constructor issuance and its event, contract deployment, exact
transfers, zero and maximum values, approvals and revocation, finite and unlimited
allowances, failure rollback, unauthorized movement, and absence of administrative
entry points. A launch distribution test models exact 10% distributor, 80% pool,
and 10% requester transfers and token transfers in both trading directions.
This is a token-flow test, not a live pool integration test. Stateful invariants
exercise transfers, approvals, and successful and failed delegated transfers
across four holders, checking supply conservation and immutable metadata.

## Deployment and operation

Deploy the creation bytecode for **`ConditionToken`** with no constructor
arguments and no ETH value. The constructor makes no external calls and needs
no initialization. In the supplied launch flow on Robinhood Chain (chain ID
4663), the factory is the deploying account and initially receives all `10^27`
base units. Direct deployment instead gives the full supply to that direct
deployer. The contract deliberately uses `msg.sender`, never `tx.origin`.

The launch operator is responsible for the later factory distribution, pool
creation, initial pricing, and token verification on the explorer. Those actions
are external to this token. No pool, distributor, paired token, or recipient
address is embedded in its bytecode, and the constructor allocates no tokens
elsewhere. No launch manifest or broadcasting script is supplied; the separate
launch process supplies its own manifest and transactions.

After launch there are no owner settings, keys, maintenance transactions, or
privileged roles for this token. Holders control their balances and approvals.
Integrations must use 18-decimal base units. Holders should approve only amounts
they intend to spend, revoke unused approvals, and consider the standard ERC-20
allowance replacement race: an already-approved spender may spend the old
allowance before a replacement transaction is mined. Waiting for a revocation
to confirm before granting a new allowance avoids overlapping approvals.
Sending tokens to a contract that cannot return them can lock them permanently;
the token has no recovery or seizure power. The deployment operator should
arrange independent review before release; local tests are not a security audit.

## Dependencies

The unmodified OpenZeppelin Contracts v5.4.0 ERC-20 implementation and its five
supporting files (including its license) are vendored in
`lib/openzeppelin-contracts/`. Forge Standard Library v1.9.7 Solidity sources
and both licenses are vendored in `lib/forge-std/` for testing only. Exact source
origins and archive checksums are recorded in `DEPENDENCIES.md`.
