# DeFi security tests

Foundry tests I wrote while reviewing live DeFi protocols. They check invariants and known attack classes against mainnet forks, plus a small local vault model for share-price fuzzing.

I am Gus Maulana (Jakarta, UTC+7). GitHub: [Agus12341](https://github.com/Agus12341).

These are review and verification tests. A passing test means the checked property held at the pinned fork block, or in the local model. This repo does not claim a vulnerability in any of the protocols.

## What's here

### CapyFi (`test/capyfi`)

Compound v2 fork on Ethereum. Tests talk to the live Unitroller through interfaces; protocol source is not vendored.

- Exchange-rate identity: `exchangeRateStored == (cash + borrows - reserves) * 1e18 / totalSupply` on every listed market, including the FX markets (wARS, wBRL, wMXN, wCOP, USDAR).
- Mint/redeem round trips on caUSDC, caETH, and caWARS, and a USDC-collateral / USDT-debt borrow, repay, and liquidation path.
- Empty-market exchange-rate inflation (the Hundred/Sonne class): donating to a thin FX market must not unlock borrow liquidity while its collateral factor is 0. A second test shows liquidity appears only after the admin sets CF.
- Oracle scaling: FX prices match `answer * 10**(36 - feedDecimals - underlyingDecimals)`. The oracle also still returns a price after the feed is aged in the fork (the acknowledged Coinspect CAPY-02 behaviour: no freshness gate).
- caLAC and caRPC mint is blocked for addresses that are not whitelisted. Pause and USDAR blocklist controls are role-gated.

Needs `ETH_RPC_URL`. Source reviewed: [Capyfi/capyfi-smart-contracts](https://github.com/Capyfi/capyfi-smart-contracts) at `99d5313e4b14b3da07e4bc8e47248cb3e18954c8`.

### Enzyme Onyx (`test/onyx`)

- `SharePriceInvariants.t.sol` is local (no RPC). It fuzzes a small fee-charging vault that models the share-price and entry/exit-fee rounding I reviewed on Onyx: a deposit then redeem at the same cached price must not pay out more than was deposited, redeeming all shares returns at most `totalAssets`, and splitting a redeem must not beat that bound by more than fee rounding. This is not Enzyme source.
- `ForkLive.t.sol` hits three live Ethereum vaults (Unsquared, CREDI, Ensuro) and checks that a sync deposit followed by a queued redeem at the same cached share price does not profit the depositor. Needs `ETH_RPC_URL`.

Source reviewed: [enzymefinance/protocol-onyx](https://github.com/enzymefinance/protocol-onyx) at `d8a522d`.

### Metric (`test/metric`)

Live-pool invariants on Ethereum and BSC, against interfaces only (`src/metric/LiveInterfaces.sol`).

- Quote lens returns a positive bid/ask with ask > bid on selected high-TVL pools.
- An exact-in swap round trip must not mint a profit above a dust bound.
- Add then remove liquidity must not credit free tokens.
- A pool with a stalled price provider must revert on quote rather than return a bad price.

Pinned fork blocks: Ethereum `26391713`, BSC `132969187` (11 Nov 2026). Needs `ETH_RPC_URL` and/or `BSC_RPC_URL`. Pool interfaces match [Metricxyz/pool-contracts](https://github.com/Metricxyz/pool-contracts).

## How to run

```bash
git clone https://github.com/Agus12341/defi-security-pocs.git
cd defi-security-pocs
forge install
forge build
```

Local tests (no RPC) should pass on their own:

```bash
forge test --match-path test/onyx/SharePriceInvariants.t.sol -vv
```

Fork tests skip if the matching env var is unset. To run them, point at any public Ethereum or BSC endpoint:

```bash
export ETH_RPC_URL=https://ethereum.publicnode.com
export BSC_RPC_URL=https://bsc.publicnode.com
forge test -vv
```

Do not broadcast transactions. These suites are local-fork or local-anvil only.

## License

MIT
