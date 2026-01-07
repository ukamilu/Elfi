# elfi

Minimal Clarity contract implementing a vault-based collateral system with an internal btcUSD-style ledger, plus admin/oracle/keeper controls.

## Contract

- Path: `contracts/elfi.clar`
- Collateral is STX; vaults track `collateral-stx`, `debt`, and `last-update` (stored as `burn-block-height`).

## Storage

- `vaults` map: `owner` -> `{ collateral-stx, debt, last-update }`
- `balances` map: internal token balance per `owner`
- `keepers` map: `keeper` -> `{ active }`
- Data vars: `admin`, `oracle`, `price`, `total-supply`

## Constants

- Error codes: `ERR-INVALID-AMOUNT`, `ERR-NOT-AUTH`, `ERR-INSUFFICIENT-COLLATERAL`, `ERR-INSUFFICIENT-BALANCE`, `ERR-NOT-FOUND`, `ERR-UNDER-COLLATERALIZED`, `ERR-PRICE-NOT-SET`, `ERR-HEALTHY`, `ERR-OVERPAY`, `ERR-NOT-KEEPER`
- Risk and scaling: `STX-SCALE` (1e6), `PRICE-SCALE` (1e8), `LTV-BPS` (5000), `BPS-SCALE` (10000), `LIQUIDATION-BONUS-BPS` (500)
- Token metadata: `TOKEN-NAME`, `TOKEN-SYMBOL`, `TOKEN-DECIMALS`

## Access Control

- `admin` can set `admin`, `oracle`, and `keepers`.
- `oracle` can update `price`.
- `keepers` (or `admin`) can call `repay-debt`.

## Internal Token Ledger

The contract tracks balances and total supply internally (`balances`, `total-supply`) and exposes a simple `transfer`. It does not implement a SIP-010 trait interface.

## Public Functions

- `set-admin`, `set-oracle`, `set-keeper`: admin configuration.
- `set-price`: oracle-controlled price update.
- `deposit`: transfers STX into the contract and updates the vault.
- `withdraw`: returns STX from the contract after collateral health checks.
- `borrow`: mints internal tokens and increases vault debt subject to LTV.
- `repay`: burns caller tokens and reduces vault debt.
- `repay-debt`: keeper-only burn from contract balance to reduce a user’s debt.
- `liquidate`: burns liquidator tokens to seize collateral when a vault is unhealthy.
- `transfer`: moves internal tokens between principals.

## Read-Only Functions

- `get-vault`, `get-balance`, `get-total-supply`, `get-price`, `get-price-scale`
- `get-admin`, `get-oracle`, `is-keeper-for`
- `get-token-name`, `get-token-symbol`, `get-token-decimals`
