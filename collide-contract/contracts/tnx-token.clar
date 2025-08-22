
;; title: tnx-token
;; version:
;; summary:
;; description:

;; TNX Token - In-game currency for purchases, rewards, staking, and governance
;; Implements SIP-010 Fungible Token Standard

(define-fungible-token tnx)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-staking-locked (err u104))

;; Data maps
(define-map authorized-minters principal bool)
(define-map token-uri (buff 32) (string-utf8 256))

;; Staking data
(define-map staking-balances principal uint)
(define-map staking-timestamps principal uint)
(define-map staking-lock-periods principal uint)

;; Governance data
(define-map proposals uint {
    title: (string-utf8 100),
    description: (string-utf8 500),
    deadline: uint,
    executed: bool
})
(define-map votes {proposal-id: uint, voter: principal} uint)
(define-data-var proposal-count uint u0)

;; SIP-010 Functions

;; Transfer tokens to a specified principal
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
        (asserts! (is-eq tx-sender sender) err-not-authorized)
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (<= amount (ft-get-balance tnx sender)) err-insufficient-balance)
        (try! (ft-transfer? tnx amount sender recipient))
        (ok true)
    )
)

;; Get the token name
(define-read-only (get-name)
    (ok "TNX Token")
)

;; Get the token symbol
(define-read-only (get-symbol)
    (ok "TNX")
)

;; Get the token decimals
(define-read-only (get-decimals)
    (ok u6)
)

;; Get the token URI
(define-read-only (get-token-uri (token-id (buff 32)))
    (ok (map-get? token-uri token-id))
)

;; Get the total supply
(define-read-only (get-total-supply)
    (ok (ft-get-supply tnx))
)

;; Get the balance of a specified principal
(define-read-only (get-balance (who principal))
    (ok (ft-get-balance tnx who))
)

;; Admin Functions

;; Set a principal as an authorized minter
(define-public (set-authorized-minter (minter principal) (authorized bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set authorized-minters minter authorized))
    )
)

;; Set the token URI
(define-public (set-token-uri (token-id (buff 32)) (uri (string-utf8 256)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set token-uri token-id uri))
    )
)

;; Mint tokens to a specified principal (only authorized minters)
(define-public (mint (amount uint) (recipient principal))
    (begin
        (asserts! (or (is-eq tx-sender contract-owner) (default-to false (map-get? authorized-minters tx-sender))) err-not-authorized)
        (asserts! (> amount u0) err-invalid-amount)
        (ok (ft-mint? tnx amount recipient))
    )
)

;; Game Reward Functions

;; Reward a player for completing a task
(define-public (reward-task-completion (player principal) (amount uint))
    (begin
        (asserts! (or (is-eq tx-sender contract-owner) (default-to false (map-get? authorized-minters tx-sender))) err-not-authorized)
        (asserts! (> amount u0) err-invalid-amount)
        (ok (ft-mint? tnx amount player))
    )
)
