
(define-constant ERR-INVALID-AMOUNT u400)
(define-constant ERR-NOT-AUTH u401)
(define-constant ERR-INSUFFICIENT-COLLATERAL u402)
(define-constant ERR-INSUFFICIENT-BALANCE u403)
(define-constant ERR-NOT-FOUND u404)
(define-constant ERR-UNDER-COLLATERALIZED u405)
(define-constant ERR-PRICE-NOT-SET u406)
(define-constant ERR-HEALTHY u407)
(define-constant ERR-OVERPAY u408)
(define-constant ERR-NOT-KEEPER u409)

(define-constant STX-SCALE u1000000)
(define-constant PRICE-SCALE u100000000)
(define-constant LTV-BPS u5000)
(define-constant BPS-SCALE u10000)
(define-constant LIQUIDATION-BONUS-BPS u500)

(define-constant TOKEN-NAME "btcUSD")
(define-constant TOKEN-SYMBOL "BTCUSD")
(define-constant TOKEN-DECIMALS u8)

(define-data-var admin principal tx-sender)
(define-data-var oracle principal tx-sender)
(define-data-var price uint u0)
(define-data-var total-supply uint u0)

(define-map vaults
    { owner: principal }
    { collateral-stx: uint, debt: uint, last-update: uint }
)

(define-map balances
    { owner: principal }
    { balance: uint }
)

(define-map keepers
    { keeper: principal }
    { active: bool }
)

(define-private (is-admin (sender principal))
    (is-eq sender (var-get admin))
)

(define-private (is-keeper (sender principal))
    (or (is-admin sender)
        (match (map-get? keepers { keeper: sender })
            keeper-entry (get active keeper-entry)
            false
        )
    )
)

(define-private (require-vault (owner principal))
    (match (map-get? vaults { owner: owner })
        vault (ok vault)
        (err ERR-NOT-FOUND)
    )
)

(define-private (read-balance (owner principal))
    (match (map-get? balances { owner: owner })
        entry (get balance entry)
        u0
    )
)

(define-private (write-balance (owner principal) (balance uint))
    (if (> balance u0)
        (map-set balances { owner: owner } { balance: balance })
        (map-delete balances { owner: owner })
    )
)

(define-private (credit (owner principal) (amount uint))
    (write-balance owner (+ (read-balance owner) amount))
)

(define-private (debit (owner principal) (amount uint))
    (let ((balance (read-balance owner)))
        (asserts! (>= balance amount) (err ERR-INSUFFICIENT-BALANCE))
        (write-balance owner (- balance amount))
        (ok true)
    )
)

(define-private (mint (owner principal) (amount uint))
    (begin
        (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
        (var-set total-supply (+ (var-get total-supply) amount))
        (credit owner amount)
        (ok true)
    )
)

(define-private (burn (owner principal) (amount uint))
    (begin
        (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
        (asserts! (>= (var-get total-supply) amount) (err ERR-INSUFFICIENT-BALANCE))
        (try! (debit owner amount))
        (var-set total-supply (- (var-get total-supply) amount))
        (ok true)
    )
)

(define-private (collateral-value (collateral uint))
    (/ (* collateral (var-get price)) STX-SCALE)
)

(define-private (max-debt (collateral uint))
    (/ (* (collateral-value collateral) LTV-BPS) BPS-SCALE)
)

(define-private (vault-healthy (collateral uint) (debt uint))
    (<= debt (max-debt collateral))
)

(define-read-only (get-vault (owner principal))
    (map-get? vaults { owner: owner })
)

(define-read-only (get-balance (owner principal))
    (read-balance owner)
)

(define-read-only (get-total-supply)
    (var-get total-supply)
)

(define-read-only (get-price)
    (var-get price)
)

(define-read-only (get-price-scale)
    PRICE-SCALE
)

(define-read-only (get-admin)
    (var-get admin)
)

(define-read-only (get-oracle)
    (var-get oracle)
)

(define-read-only (is-keeper-for (sender principal))
    (is-keeper sender)
)

(define-read-only (get-token-name)
    TOKEN-NAME
)

(define-read-only (get-token-symbol)
    TOKEN-SYMBOL
)

(define-read-only (get-token-decimals)
    TOKEN-DECIMALS
)

(define-public (set-admin (new-admin principal))
    (begin
        (asserts! (is-admin tx-sender) (err ERR-NOT-AUTH))
        (var-set admin new-admin)
        (ok true)
    )
)

(define-public (set-oracle (new-oracle principal))
    (begin
        (asserts! (is-admin tx-sender) (err ERR-NOT-AUTH))
        (var-set oracle new-oracle)
        (ok true)
    )
)

(define-public (set-keeper (keeper principal) (active bool))
    (begin
        (asserts! (is-admin tx-sender) (err ERR-NOT-AUTH))
        (if active
            (map-set keepers { keeper: keeper } { active: true })
            (map-delete keepers { keeper: keeper })
        )
        (ok true)
    )
)

(define-public (set-price (new-price uint))
    (begin
        (asserts! (is-eq tx-sender (var-get oracle)) (err ERR-NOT-AUTH))
        (asserts! (> new-price u0) (err ERR-INVALID-AMOUNT))
        (var-set price new-price)
        (ok true)
    )
)

;; 1. Deposit Collateral
(define-public (deposit (amount uint))
    (begin
        (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (match (map-get? vaults { owner: tx-sender })
            vault
                (map-set vaults { owner: tx-sender }
                    { collateral-stx: (+ (get collateral-stx vault) amount),
                      debt: (get debt vault),
                      last-update: burn-block-height
                    }
                )
            (map-set vaults { owner: tx-sender }
                { collateral-stx: amount,
                  debt: u0,
                  last-update: burn-block-height
                }
            )
        )
        (ok true)
    )
)

;; 2. Withdraw Collateral
(define-public (withdraw (amount uint))
    (let ((vault (try! (require-vault tx-sender)))
          (recipient tx-sender))
        (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
        (asserts! (>= (get collateral-stx vault) amount) (err ERR-INSUFFICIENT-BALANCE))
        (let ((new-collateral (- (get collateral-stx vault) amount)))
            (if (> (get debt vault) u0)
                (asserts! (> (var-get price) u0) (err ERR-PRICE-NOT-SET))
                true
            )
            (asserts! (vault-healthy new-collateral (get debt vault)) (err ERR-UNDER-COLLATERALIZED))
            (map-set vaults { owner: tx-sender }
                { collateral-stx: new-collateral,
                  debt: (get debt vault),
                  last-update: burn-block-height
                }
            )
            (try! (as-contract (stx-transfer? amount tx-sender recipient)))
            (ok true)
        )
    )
)

;; 3. Borrow Synthetic
(define-public (borrow (amount uint))
    (let ((vault (try! (require-vault tx-sender)))
          (current-price (var-get price)))
        (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
        (asserts! (> current-price u0) (err ERR-PRICE-NOT-SET))
        (let ((new-debt (+ (get debt vault) amount))
              (max-allowed (max-debt (get collateral-stx vault))))
            (asserts! (<= new-debt max-allowed) (err ERR-INSUFFICIENT-COLLATERAL))
            (map-set vaults { owner: tx-sender }
                { collateral-stx: (get collateral-stx vault),
                  debt: new-debt,
                  last-update: burn-block-height
                }
            )
            (try! (mint tx-sender amount))
            (ok new-debt)
        )
    )
)

;; 4. User Repay
(define-public (repay (amount uint))
    (let ((vault (try! (require-vault tx-sender))))
        (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
        (asserts! (<= amount (get debt vault)) (err ERR-OVERPAY))
        (try! (burn tx-sender amount))
        (map-set vaults { owner: tx-sender }
            { collateral-stx: (get collateral-stx vault),
              debt: (- (get debt vault) amount),
              last-update: burn-block-height
            }
        )
        (ok true)
    )
)

;; 5. Keeper Repay (Protocol Yield)
(define-public (repay-debt (user principal) (yield-amount-sbtc uint))
    (begin
        (asserts! (is-keeper tx-sender) (err ERR-NOT-KEEPER))
        (asserts! (> yield-amount-sbtc u0) (err ERR-INVALID-AMOUNT))
        (let ((vault (try! (require-vault user)))
              (contract-principal (as-contract tx-sender)))
            (asserts! (<= yield-amount-sbtc (get debt vault)) (err ERR-OVERPAY))
            (try! (burn contract-principal yield-amount-sbtc))
            (map-set vaults { owner: user }
                { collateral-stx: (get collateral-stx vault),
                  debt: (- (get debt vault) yield-amount-sbtc),
                  last-update: burn-block-height
                }
            )
            (ok true)
        )
    )
)

;; 6. Liquidation
(define-public (liquidate (owner principal) (repay-amount uint))
    (let ((vault (try! (require-vault owner)))
          (current-price (var-get price))
          (liquidator tx-sender))
        (asserts! (> repay-amount u0) (err ERR-INVALID-AMOUNT))
        (asserts! (> current-price u0) (err ERR-PRICE-NOT-SET))
        (asserts! (not (vault-healthy (get collateral-stx vault) (get debt vault))) (err ERR-HEALTHY))
        (asserts! (<= repay-amount (get debt vault)) (err ERR-OVERPAY))
        (let ((base-collateral (/ (* repay-amount STX-SCALE) current-price))
              (bonus (/ (* base-collateral LIQUIDATION-BONUS-BPS) BPS-SCALE))
              (total-seize (+ base-collateral bonus)))
            (asserts! (> total-seize u0) (err ERR-INVALID-AMOUNT))
            (asserts! (<= total-seize (get collateral-stx vault)) (err ERR-INSUFFICIENT-COLLATERAL))
            (try! (burn liquidator repay-amount))
            (map-set vaults { owner: owner }
                { collateral-stx: (- (get collateral-stx vault) total-seize),
                  debt: (- (get debt vault) repay-amount),
                  last-update: burn-block-height
                }
            )
            (try! (as-contract (stx-transfer? total-seize tx-sender liquidator)))
            (ok total-seize)
        )
    )
)

;; 7. Simple Token Transfer
(define-public (transfer (amount uint) (sender principal) (recipient principal))
    (begin
        (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
        (asserts! (is-eq sender tx-sender) (err ERR-NOT-AUTH))
        (try! (debit sender amount))
        (credit recipient amount)
        (ok true)
    )
)
