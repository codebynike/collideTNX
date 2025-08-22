;; Game NFT Contract
;; Self-contained NFT implementation for game assets

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-not-found (err u102))
(define-constant err-sender-equals-recipient (err u103))
(define-constant err-not-authorized (err u104))
(define-constant err-token-exists (err u105))
(define-constant err-invalid-metadata (err u106))

;; NFT Definition
(define-non-fungible-token game-nft uint)

;; Data Variables
(define-data-var last-token-id uint u0)
(define-data-var contract-uri (optional (string-utf8 256)) none)

;; Token metadata map
(define-map token-metadata
  uint ;; token-id
  {
    name: (string-utf8 64),
    description: (string-utf8 256),
    image-uri: (string-utf8 256),
    rarity: (string-ascii 16),
    attributes: (string-utf8 1024)
  }
)

;; Approved operators for each token
(define-map token-approvals
  {token-id: uint, approved: principal}
  bool
)

;; Approved operators for all tokens of an owner
(define-map operator-approvals
  {owner: principal, operator: principal}
  bool
)

;; Token URI map (optional individual URIs)
(define-map token-uris
  uint
  (string-utf8 256)
)

;; Helper Functions
(define-private (is-owner (token-id uint) (user principal))
  (is-eq user (unwrap! (nft-get-owner? game-nft token-id) false))
)

(define-private (is-approved-or-owner (token-id uint) (user principal))
  (or 
    (is-owner token-id user)
    (is-approved token-id user)
    (match (nft-get-owner? game-nft token-id)
      some-owner (is-approved-for-all some-owner user)
      false
    )
  )
)

(define-private (is-approved (token-id uint) (user principal))
  (default-to false (map-get? token-approvals {token-id: token-id, approved: user}))
)

(define-private (is-approved-for-all (owner principal) (operator principal))
  (default-to false (map-get? operator-approvals {owner: owner, operator: operator}))
)

;; Core NFT Functions

;; Get the last minted token ID
(define-read-only (get-last-token-id)
  (var-get last-token-id)
)

;; Get token URI
(define-read-only (get-token-uri (token-id uint))
  (map-get? token-uris token-id)
)

;; Get the owner of a specific token
(define-read-only (get-owner (token-id uint))
  (nft-get-owner? game-nft token-id)
)

;; Transfer function
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (not (is-eq sender recipient)) err-sender-equals-recipient)
    (asserts! (is-approved-or-owner token-id tx-sender) err-not-authorized)
    
    ;; Clear any existing approvals for this token
    (map-delete token-approvals {token-id: token-id, approved: tx-sender})
    
    ;; Transfer the NFT
    (nft-transfer? game-nft token-id sender recipient)
  )
)

;; Simple transfer (for marketplace compatibility)
(define-public (transfer-token (token-id uint) (from principal) (to principal))
  (transfer token-id from to)
)

;; Mint function (owner only)
(define-public (mint (recipient principal) (metadata {name: (string-utf8 64), description: (string-utf8 256), image-uri: (string-utf8 256), rarity: (string-ascii 16), attributes: (string-utf8 1024)}))
  (let ((token-id (+ (var-get last-token-id) u1)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    ;; Mint the NFT
    (unwrap! (nft-mint? game-nft token-id recipient) (err u999))
    
    ;; Set metadata
    (map-set token-metadata token-id metadata)
    
    ;; Update last token ID
    (var-set last-token-id token-id)
    
    ;; Emit mint event
    (print {
      event: "nft-minted",
      token-id: token-id,
      recipient: recipient,
      metadata: metadata
    })
    
    (ok token-id)
  )
)

;; Batch mint function
(define-public (batch-mint (recipients (list 25 principal)) (metadatas (list 25 {name: (string-utf8 64), description: (string-utf8 256), image-uri: (string-utf8 256), rarity: (string-ascii 16), attributes: (string-utf8 1024)})))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-eq (len recipients) (len metadatas)) err-invalid-metadata)
    
    (let ((pairs (zip-lists recipients metadatas)))
      (ok (fold mint-single-item pairs u0))
    )
  )
)

(define-private (zip-lists (recipients (list 25 principal)) (metadatas (list 25 {name: (string-utf8 64), description: (string-utf8 256), image-uri: (string-utf8 256), rarity: (string-ascii 16), attributes: (string-utf8 1024)})))
  (map create-mint-pair recipients metadatas)
)

(define-private (create-mint-pair (recipient principal) (metadata {name: (string-utf8 64), description: (string-utf8 256), image-uri: (string-utf8 256), rarity: (string-ascii 16), attributes: (string-utf8 1024)}))
  {recipient: recipient, metadata: metadata}
)

(define-private (mint-single-item (pair {recipient: principal, metadata: {name: (string-utf8 64), description: (string-utf8 256), image-uri: (string-utf8 256), rarity: (string-ascii 16), attributes: (string-utf8 1024)}}) (counter uint))
  (let (
    (token-id (+ (var-get last-token-id) u1))
    (recipient (get recipient pair))
    (metadata (get metadata pair))
  )
    (unwrap-panic (nft-mint? game-nft token-id recipient))
    (map-set token-metadata token-id metadata)
    (var-set last-token-id token-id)
    (+ counter u1)
  )
)

(define-private (mint-batch-helper (recipients (list 25 principal)) (metadatas (list 25 {name: (string-utf8 64), description: (string-utf8 256), image-uri: (string-utf8 256), rarity: (string-ascii 16), attributes: (string-utf8 1024)})) (index uint))
  index
)

;; Burn function
(define-public (burn (token-id uint))
  (let ((owner (unwrap! (nft-get-owner? game-nft token-id) err-not-found)))
    (asserts! (is-approved-or-owner token-id tx-sender) err-not-authorized)
    
    ;; Clear metadata and approvals
    (map-delete token-metadata token-id)
    (map-delete token-approvals {token-id: token-id, approved: tx-sender})
    (map-delete token-uris token-id)
    
    ;; Burn the NFT
    (nft-burn? game-nft token-id owner)
  )
)

;; Approval Functions

;; Approve a specific user for a specific token
(define-public (approve (token-id uint) (approved principal))
  (let ((owner (unwrap! (nft-get-owner? game-nft token-id) err-not-found)))
    (asserts! (is-eq tx-sender owner) err-not-token-owner)
    (asserts! (not (is-eq owner approved)) err-sender-equals-recipient)
    
    (map-set token-approvals {token-id: token-id, approved: approved} true)
    (print {event: "approval", token-id: token-id, owner: owner, approved: approved})
    (ok true)
  )
)

;; Approve/revoke an operator for all tokens
(define-public (set-approval-for-all (operator principal) (approved bool))
  (begin
    (asserts! (not (is-eq tx-sender operator)) err-sender-equals-recipient)
    
    (map-set operator-approvals {owner: tx-sender, operator: operator} approved)
    (print {event: "approval-for-all", owner: tx-sender, operator: operator, approved: approved})
    (ok true)
  )
)

;; Read-only functions

;; Get token metadata
(define-read-only (get-token-metadata (token-id uint))
  (map-get? token-metadata token-id)
)

;; Get approved user for token
(define-read-only (get-approved (token-id uint))
  (map-get? token-approvals {token-id: token-id, approved: tx-sender})
)

;; Check if operator is approved for all tokens of owner
(define-read-only (is-approved-for-all-tokens (owner principal) (operator principal))
  (default-to false (map-get? operator-approvals {owner: owner, operator: operator}))
)

;; Get total supply
(define-read-only (get-total-supply)
  (var-get last-token-id)
)

;; Check if token exists
(define-read-only (token-exists (token-id uint))
  (is-some (nft-get-owner? game-nft token-id))
)

;; Get contract metadata
(define-read-only (get-contract-uri)
  (var-get contract-uri)
)

;; Check ownership (for marketplace)
(define-read-only (is-token-owner (token-id uint) (user principal))
  (is-eq (some user) (nft-get-owner? game-nft token-id))
)

;; Admin functions

;; Set contract URI
(define-public (set-contract-uri (uri (string-utf8 256)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-uri (some uri))
    (ok true)
  )
)

;; Set individual token URI
(define-public (set-token-uri (token-id uint) (uri (string-utf8 256)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (token-exists token-id) err-not-found)
    (map-set token-uris token-id uri)
    (ok true)
  )
)

;; Update token metadata (owner only)
(define-public (update-token-metadata (token-id uint) (metadata {name: (string-utf8 64), description: (string-utf8 256), image-uri: (string-utf8 256), rarity: (string-ascii 16), attributes: (string-utf8 1024)}))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (token-exists token-id) err-not-found)
    (map-set token-metadata token-id metadata)
    (ok true)
  )
)