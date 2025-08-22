;; NFT Marketplace Smart Contract
;; Handles listing, buying, and selling of NFTs with TNX token payments

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-listing-not-found (err u102))
(define-constant err-insufficient-payment (err u103))
(define-constant err-already-listed (err u104))
(define-constant err-not-listed (err u105))
(define-constant err-cannot-buy-own-nft (err u106))
(define-constant err-transfer-failed (err u107))
(define-constant err-invalid-price (err u108))

;; Marketplace fee (2.5% = 250 basis points)
(define-constant marketplace-fee-bps u250)
(define-constant basis-points u10000)

;; Data Variables
(define-data-var marketplace-enabled bool true)
(define-data-var next-listing-id uint u1)

;; Data Maps
(define-map listings
  uint ;; listing-id
  {
    nft-contract: principal,
    token-id: uint,
    seller: principal,
    price: uint,
    active: bool
  }
)

(define-map nft-to-listing
  {nft-contract: principal, token-id: uint}
  uint ;; listing-id
)

(define-map user-listings
  principal ;; user
  (list 100 uint) ;; list of listing-ids
)

;; Helper Functions
(define-private (is-contract-owner)
  (is-eq tx-sender contract-owner)
)

(define-private (calculate-marketplace-fee (price uint))
  (/ (* price marketplace-fee-bps) basis-points)
)

(define-private (calculate-seller-amount (price uint))
  (- price (calculate-marketplace-fee price))
)

;; Private function to check if caller owns the NFT
(define-private (check-nft-ownership (nft-contract principal) (token-id uint) (owner principal))
  (contract-call? .game-nft is-token-owner token-id owner)
)

;; Private function to add listing to user's listing history
(define-private (add-to-user-listings (user principal) (listing-id uint))
  (let ((current-listings (default-to (list) (map-get? user-listings user))))
    (match (as-max-len? (append current-listings listing-id) u100)
      some-list (begin (map-set user-listings user some-list) (ok true))
      (err u999)
    )
  )
)

;; Private function to remove listing from user's listing history
(define-private (remove-from-user-listings (user principal) (listing-id uint))
  (let ((current-listings (default-to (list) (map-get? user-listings user))))
    (begin
      (var-set current-listing-to-remove listing-id)
      (map-set user-listings user (filter is-not-target-listing current-listings))
      (ok true)
    )
  )
)

(define-private (is-not-target-listing (id uint))
  (not (is-eq id (var-get current-listing-to-remove)))
)

(define-data-var current-listing-to-remove uint u0)

;; Public Functions

;; List an NFT for sale
(define-public (list-nft (nft-contract principal) (token-id uint) (price uint))
  (let (
    (listing-id (var-get next-listing-id))
    (listing-key {nft-contract: nft-contract, token-id: token-id})
  )
    ;; Validate inputs
    (asserts! (var-get marketplace-enabled) err-not-authorized)
    (asserts! (> price u0) err-invalid-price)
    (asserts! (is-none (map-get? nft-to-listing listing-key)) err-already-listed)
    
    ;; Check if sender owns the NFT (you'll need to implement this based on your NFT contract)
    (asserts! (check-nft-ownership nft-contract token-id tx-sender) err-not-authorized)
    
    ;; Create listing
    (map-set listings listing-id {
      nft-contract: nft-contract,
      token-id: token-id,
      seller: tx-sender,
      price: price,
      active: true
    })
    
    ;; Map NFT to listing
    (map-set nft-to-listing listing-key listing-id)
    
    ;; Add to user's listings
    (unwrap! (add-to-user-listings tx-sender listing-id) err-transfer-failed)
    
    ;; Increment listing ID counter
    (var-set next-listing-id (+ listing-id u1))
    
    ;; Emit event (print for now)
    (print {
      event: "nft-listed",
      listing-id: listing-id,
      nft-contract: nft-contract,
      token-id: token-id,
      seller: tx-sender,
      price: price
    })
    
    (ok listing-id)
  )
)

;; Update listing price
(define-public (update-listing-price (listing-id uint) (new-price uint))
  (let ((listing (unwrap! (map-get? listings listing-id) err-listing-not-found)))
    ;; Validate
    (asserts! (var-get marketplace-enabled) err-not-authorized)
    (asserts! (> new-price u0) err-invalid-price)
    (asserts! (is-eq tx-sender (get seller listing)) err-not-authorized)
    (asserts! (get active listing) err-not-listed)
    
    ;; Update listing
    (map-set listings listing-id (merge listing {price: new-price}))
    
    ;; Emit event
    (print {
      event: "listing-price-updated",
      listing-id: listing-id,
      old-price: (get price listing),
      new-price: new-price
    })
    
    (ok true)
  )
)

;; Cancel a listing
(define-public (cancel-listing (listing-id uint))
  (let ((listing (unwrap! (map-get? listings listing-id) err-listing-not-found)))
    ;; Validate
    (asserts! (var-get marketplace-enabled) err-not-authorized)
    (asserts! (is-eq tx-sender (get seller listing)) err-not-authorized)
    (asserts! (get active listing) err-not-listed)
    
    ;; Deactivate listing
    (map-set listings listing-id (merge listing {active: false}))
    
    ;; Remove NFT mapping
    (map-delete nft-to-listing {
      nft-contract: (get nft-contract listing),
      token-id: (get token-id listing)
    })
    
    ;; Remove from user listings
    (var-set current-listing-to-remove listing-id)
    (unwrap! (remove-from-user-listings tx-sender listing-id) err-transfer-failed)
    
    ;; Emit event
    (print {
      event: "listing-cancelled",
      listing-id: listing-id,
      seller: tx-sender
    })
    
    (ok true)
  )
)

;; Buy an NFT from the marketplace
(define-public (buy-nft (listing-id uint))
  (let (
    (listing (unwrap! (map-get? listings listing-id) err-listing-not-found))
    (price (get price listing))
    (seller (get seller listing))
    (marketplace-fee (calculate-marketplace-fee price))
    (seller-amount (calculate-seller-amount price))
  )
    ;; Validate
    (asserts! (var-get marketplace-enabled) err-not-authorized)
    (asserts! (get active listing) err-not-listed)
    (asserts! (not (is-eq tx-sender seller)) err-cannot-buy-own-nft)
    
    ;; Transfer TNX tokens from buyer to seller
    (unwrap! (contract-call? .tnx-token transfer seller-amount tx-sender seller none) err-transfer-failed)
    
    ;; Transfer marketplace fee to contract owner
    (unwrap! (contract-call? .tnx-token transfer marketplace-fee tx-sender contract-owner none) err-transfer-failed)
    
    ;; Transfer NFT from seller to buyer
    (unwrap! (contract-call? .game-nft transfer-token (get token-id listing) seller tx-sender) err-transfer-failed)
    
    ;; Deactivate listing
    (map-set listings listing-id (merge listing {active: false}))
    
    ;; Remove NFT mapping
    (map-delete nft-to-listing {
      nft-contract: (get nft-contract listing),
      token-id: (get token-id listing)
    })
    
    ;; Remove from seller's listings
    (var-set current-listing-to-remove listing-id)
    (unwrap! (remove-from-user-listings seller listing-id) err-transfer-failed)
    
    ;; Emit event
    (print {
      event: "nft-sold",
      listing-id: listing-id,
      buyer: tx-sender,
      seller: seller,
      price: price,
      marketplace-fee: marketplace-fee
    })
    
    (ok true)
  )
)

;; Read-only functions

;; Get listing details
(define-read-only (get-listing (listing-id uint))
  (map-get? listings listing-id)
)

;; Get listing ID for a specific NFT
(define-read-only (get-nft-listing (nft-contract principal) (token-id uint))
  (map-get? nft-to-listing {nft-contract: nft-contract, token-id: token-id})
)

;; Get user's listings
(define-read-only (get-user-listings (user principal))
  (default-to (list) (map-get? user-listings user))
)

;; Check if NFT is listed
(define-read-only (is-nft-listed (nft-contract principal) (token-id uint))
  (is-some (map-get? nft-to-listing {nft-contract: nft-contract, token-id: token-id}))
)

;; Get marketplace fee for a price
(define-read-only (get-marketplace-fee (price uint))
  (calculate-marketplace-fee price)
)

;; Get seller amount after fee deduction
(define-read-only (get-seller-amount (price uint))
  (calculate-seller-amount price)
)

;; Get next listing ID
(define-read-only (get-next-listing-id)
  (var-get next-listing-id)
)

;; Check if marketplace is enabled
(define-read-only (is-marketplace-enabled)
  (var-get marketplace-enabled)
)

;; Admin functions (contract owner only)

;; Enable/disable marketplace
(define-public (set-marketplace-enabled (enabled bool))
  (begin
    (asserts! (is-contract-owner) err-owner-only)
    (var-set marketplace-enabled enabled)
    (print {event: "marketplace-status-changed", enabled: enabled})
    (ok true)
  )
)

;; Emergency function to cancel any listing (admin only)
(define-public (admin-cancel-listing (listing-id uint))
  (let ((listing (unwrap! (map-get? listings listing-id) err-listing-not-found)))
    (asserts! (is-contract-owner) err-owner-only)
    (asserts! (get active listing) err-not-listed)
    
    ;; Deactivate listing
    (map-set listings listing-id (merge listing {active: false}))
    
    ;; Remove NFT mapping
    (map-delete nft-to-listing {
      nft-contract: (get nft-contract listing),
      token-id: (get token-id listing)
    })
    
    ;; Emit event
    (print {
      event: "admin-listing-cancelled",
      listing-id: listing-id,
      original-seller: (get seller listing)
    })
    
    (ok true)
  )
)