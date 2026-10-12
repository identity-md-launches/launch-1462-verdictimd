# VerdictIMD (VERDICT)

A fixed-supply ERC-20 for the IdentityMD custom-token launch. The complete supply is
minted once to the immediate deployer in the constructor.

| Property | Value |
| --- | --- |
| Solidity contract | `VerdictIMD` |
| Source | `src/VerdictIMD.sol` |
| Token name | `VerdictIMD` |
| Symbol | `VERDICT` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Deployment ETH value | `0` |
| Initial recipient | Constructor `msg.sender` |
| Launch chain | Ethereum, chain ID `1` |

## Behavior and assumptions

The brief specifies an ordinary transferable token. This implementation uses the
vendored [OpenZeppelin Contracts v5.0.2 ERC20](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC20/ERC20.sol)
without transfer overrides. Every successful transfer delivers exactly the amount
specified. There are no fees, rebases, transfer limits, vesting, or recipient callbacks.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert with
ERC-20 custom errors on failure. Transfers to the zero address and approvals to a
zero spender revert. Zero-value transfers to valid addresses and self-transfers are
supported. A self-transfer still requires enough balance. Finite allowances decrease
when spent; `type(uint256).max` is treated as an unlimited allowance. Calling
`approve` replaces the previous allowance, including revoking it with `0`.

The constructor emits one `Transfer` from the zero address. Transfers emit `Transfer`
and explicit approvals emit `Approval`. In the vendored implementation,
`transferFrom` does not emit an additional `Approval` when it spends an allowance;
integrations should read `allowance()` for its current value. These semantics follow
the [ERC-20 interface](https://eips.ethereum.org/EIPS/eip-20).

There is no owner, minter, administrator, initializer, proxy, upgrade mechanism,
pause, blacklist, confiscation, public burn, or public mint entry point. Total supply
remains fixed for the lifetime of this deployed contract. The deployer has only the
same balance and allowance rights as any other holder after construction.

## Build and check

From the repository root, with Foundry and Solidity `0.8.26` available:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity `0.8.26`, the Cancun EVM, optimizer enabled with 200
runs, and `bytecode_hash = "none"`. FFI and filesystem permissions are disabled.
All Solidity dependencies are ordinary files in `lib/`; builds and tests do not
need dependency downloads, RPC access, private keys, or environment variables.
The verification worker supplies the pinned compiler. No compiler binary is
included in this repository.

`lib/DEPENDENCIES.json` records upstream tags, download archive hashes, and SHA-256
hashes of every vendored file. OpenZeppelin includes only the ERC-20 dependency
closure and its MIT license. Forge Standard Library v1.9.6 includes its Solidity
sources and MIT/Apache licenses. Upstream files are unmodified and excluded from
local formatting. There are no Git submodules or package-install steps.

## Deployment and launch handoff

Build the artifact `out/VerdictIMD.sol/VerdictIMD.json`. Its creation bytecode is
ready for deployment as-is: there are no constructor arguments to append, no library
addresses to link, no external calls from the constructor, and no initialization
transaction. The runtime artifact is the deployed bytecode, not the creation code.

The authorized launch process deploys `VerdictIMD` through the factory. The factory,
as the immediate creator, receives all `10^27` base units; the transaction sender
does not receive them unless that sender directly deploys the token. The supplied
launch process then handles allocation and liquidity. No deployment script or
broadcast is required by this deliverable, and no transaction has been submitted.

The separate manifest step owns `launch.json`. Its token entry should refer to
Solidity identifier `VerdictIMD`, the metadata and raw supply above, and an empty
constructor-argument list. There are no application contracts in this project.

For the supplied launch economics, the factory is responsible for transferring
100,000,000 tokens to its Merkle distributor, allocating 800,000,000 tokens to the
pool, and forwarding the remaining 100,000,000 tokens to
`0xbb85c1b7540d9e7b56f7a595fc1ff7dd07cb0823`. These are subsequent factory operations,
not constructor allocations or reserved balances in this token. Pairing, pricing,
fees, and pool configuration also belong to the launch process; the token has no
DEX-specific configuration or exemptions.

## After launch

There are no owner-settable values, external-service settings, keeper jobs, or
maintenance transactions. No requester-held address or key is needed to configure
the token.

The launch operator must confirm the deployed source/artifact, metadata, total supply,
initial factory mint event, and completed allocation; verify the source on the block
explorer; and retain the deployment address and transaction records. The launch
operator manages distribution and liquidity outside this token. Independent security
review before release remains a separate responsibility.

Holders manage their balances and approvals. Approvals should be limited to intended
spending; unlimited allowances remain valid until revoked. When replacing an active
allowance, clients should first revoke it and confirm that transaction to address the
standard ERC-20 allowance-change race. Tokens sent to this token contract or to a
recipient without a withdrawal mechanism cannot be recovered by an administrator.
Direct ETH transfers revert because there is no payable entry point.

## Test coverage and review limits

- `test/VerdictIMD.t.sol`: metadata, exact constructor supply and mint event,
  immediate deployer versus transaction origin, transfer and approval events,
  exact balance changes, full-supply transfers, zero-value and self-transfers,
  allowance exhaustion/revocation/infinite approvals, authorization failures,
  balance failures, zero-address rejection, and rollback of allowance changes
  when a transfer fails. It also probes absent privileged functions and checks
  runtime size and forbidden opcodes.
- `test/LaunchCompatibility.t.sol`: actual CREATE2 deployment from a local factory,
  exact factory/distributor/claim/pool custody transfers, and transfer to a recipient
  whose fallback reverts. This tests the token side of launch compatibility; it
  does not execute Uniswap liquidity or swap accounting.
- `test/VerdictIMD.invariant.t.sol`: sequences of transfers, approvals, delegated
  transfers, and rejected overdraws across four actors. All balances and allowances
  are checked against an independent model, with conservation of the entire supply.

The default suite uses 512 cases per fuzz test and 128 invariant runs of depth 64.
Tests create independent local state and can run in parallel with an empty
environment. Test-only addresses and factory helpers are not deployment settings.

The supplied security reference was reviewed for relevant failure modes. The only
production addition to OpenZeppelin is a constant and the constructor mint. There
are no external interactions, oracle reads, signature paths, upgrade storage, or
administrative powers. A reentrancy guard is unnecessary because token operations
never invoke recipients or other contracts. Foundry build, unit/fuzz/invariant tests,
and formatting checks are the local validation; Slither, Mythril, a live-chain launch,
and the network's environment-driven protected integration harness are not run here.
This local review and testing do not constitute an independent security audit.
