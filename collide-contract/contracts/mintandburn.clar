;; TNX-token
;; A fungible token for in-game economy with minting and burning capabilities

;; Define the TNX token
(define-fungible-token tnx-token)

;; Define contract owner
(define-data-var contract-owner principal tx-sender)

;; Error codes
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))

;; Read-only functions

;; Get the token balance for a given account
(define-read-only (get-balance (account principal))
  (ft-get-balance tnx-token account))

;; Get the total supply of tokens
(define-read-only (get-total-supply)
  (ft-get-supply tnx-token))

;; Check if the caller is the contract owner
(define-read-only (is-contract-owner (caller principal))
  (is-eq caller (var-get contract-owner)))

;; Public functions

;; Transfer tokens between accounts
(define-public (transfer (amount uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) (err u102))
    (ft-transfer? tnx-token amount sender recipient)))

;; Mint new tokens when players earn them from gameplay
;; Can only be called by the contract owner or authorized game servers
(define-public (mint (recipient principal) (amount uint))
  (begin
    (asserts! (is-contract-owner tx-sender) err-owner-only)
    (ft-mint? tnx-token amount recipient)))

;; Burn tokens when used in certain in-game transactions
;; Can be called by users to burn their own tokens or by the contract owner
(define-public (burn (burner principal) (amount uint))
  (begin
    (asserts! (or (is-eq tx-sender burner) (is-contract-owner tx-sender)) err-owner-only)
    (asserts! (<= amount (ft-get-balance tnx-token burner)) err-insufficient-balance)
    (ft-burn? tnx-token amount burner)))

;; Administrative functions

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner tx-sender) err-owner-only)
    (var-set contract-owner new-owner)
    (ok true)))

