;; TNX Liquidity Pool Smart Contract
;; Allows staking of TNX tokens and NFTs with reward distribution

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-AUTHORIZED (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-INSUFFICIENT-BALANCE (err u103))
(define-constant ERR-POOL-NOT-FOUND (err u104))
(define-constant ERR-ALREADY-STAKED (err u105))
(define-constant ERR-NOT-STAKED (err u106))
(define-constant ERR-EARLY-WITHDRAWAL (err u107))
(define-constant ERR-NFT-NOT-OWNED (err u108))
(define-constant ERR-INVALID-NFT (err u109))

;; Data Variables
(define-data-var total-pools uint u0)
(define-data-var reward-rate uint u100) ;; Base reward rate (1% = 100 basis points)
(define-data-var early-withdrawal-penalty uint u1000) ;; 10% penalty
(define-data-var minimum-stake-period uint u144) ;; ~1 day in blocks

;; Pool structure
(define-map pools
  { pool-id: uint }
  {
    name: (string-ascii 50),
    total-tnx-staked: uint,
    total-nfts-staked: uint,
    reward-multiplier: uint,
    is-active: bool,
    created-at: uint
  }
)

;; User stakes in pools
(define-map user-stakes
  { user: principal, pool-id: uint }
  {
    tnx-amount: uint,
    nft-ids: (list 10 uint),
    stake-timestamp: uint,
    last-reward-claim: uint,
    total-rewards-earned: uint
  }
)

;; NFT staking records
(define-map staked-nfts
  { nft-id: uint }
  {
    owner: principal,
    pool-id: uint,
    stake-timestamp: uint
  }
)

;; Reward pool balance
(define-data-var reward-pool-balance uint u0)

;; Pool statistics
(define-map pool-stats
  { pool-id: uint }
  {
    total-participants: uint,
    total-rewards-distributed: uint,
    average-stake-duration: uint
  }
)

;; Read-only functions

;; Get pool information
(define-read-only (get-pool-info (pool-id uint))
  (map-get? pools { pool-id: pool-id })
)

;; Get user stake information
(define-read-only (get-user-stake (user principal) (pool-id uint))
  (map-get? user-stakes { user: user, pool-id: pool-id })
)

;; Calculate pending rewards for a user
(define-read-only (calculate-pending-rewards (user principal) (pool-id uint))
  (let (
    (stake-info (unwrap! (get-user-stake user pool-id) (err u0)))
    (pool-info (unwrap! (get-pool-info pool-id) (err u0)))
    (blocks-since-last-claim (- stacks-block-height (get last-reward-claim stake-info)))
    (base-reward (/ (* (get tnx-amount stake-info) (var-get reward-rate)) u10000))
    (nft-bonus (/ (* (len (get nft-ids stake-info)) base-reward) u10))
    (pool-multiplier (get reward-multiplier pool-info))
  )
    (ok (/ (* (+ base-reward nft-bonus) pool-multiplier blocks-since-last-claim) u144))
  )
)

;; Check if NFT is staked
(define-read-only (is-nft-staked (nft-id uint))
  (is-some (map-get? staked-nfts { nft-id: nft-id }))
)

;; Get total value locked in pool
(define-read-only (get-pool-tvl (pool-id uint))
  (match (get-pool-info pool-id)
    pool-data (ok (get total-tnx-staked pool-data))
    (err ERR-POOL-NOT-FOUND)
  )
)

;; Public functions

;; Create a new liquidity pool (owner only)
(define-public (create-pool (name (string-ascii 50)) (reward-multiplier uint))
  (let (
    (new-pool-id (+ (var-get total-pools) u1))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> reward-multiplier u0) ERR-INVALID-AMOUNT)
    
    (map-set pools
      { pool-id: new-pool-id }
      {
        name: name,
        total-tnx-staked: u0,
        total-nfts-staked: u0,
        reward-multiplier: reward-multiplier,
        is-active: true,
        created-at: stacks-block-height
      }
    )
    
    (map-set pool-stats
      { pool-id: new-pool-id }
      {
        total-participants: u0,
        total-rewards-distributed: u0,
        average-stake-duration: u0
      }
    )
    
    (var-set total-pools new-pool-id)
    (ok new-pool-id)
  )
)

;; Stake TNX tokens and NFTs in a pool
(define-public (stake-in-pool (pool-id uint) (tnx-amount uint) (nft-ids (list 10 uint)))
  (let (
    (pool-info (unwrap! (get-pool-info pool-id) ERR-POOL-NOT-FOUND))
    (existing-stake (map-get? user-stakes { user: tx-sender, pool-id: pool-id }))
  )
    (asserts! (get is-active pool-info) ERR-NOT-AUTHORIZED)
    (asserts! (> tnx-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-none existing-stake) ERR-ALREADY-STAKED)
    
    ;; Validate NFT ownership (simplified - in practice, you'd check actual NFT contract)
    (asserts! (validate-nft-ownership nft-ids) ERR-NFT-NOT-OWNED)
    
    ;; Transfer TNX tokens to contract (simplified)
    ;; In practice: (try! (contract-call? .tnx-token transfer tnx-amount tx-sender (as-contract tx-sender) none))
    
    ;; Record the stake
    (map-set user-stakes
      { user: tx-sender, pool-id: pool-id }
      {
        tnx-amount: tnx-amount,
        nft-ids: nft-ids,
        stake-timestamp: stacks-block-height,
        last-reward-claim: stacks-block-height,
        total-rewards-earned: u0
      }
    )
    
    ;; Record staked NFTs
    (map stake-nft-records nft-ids)
    
    ;; Update pool totals
    (map-set pools
      { pool-id: pool-id }
      (merge pool-info {
        total-tnx-staked: (+ (get total-tnx-staked pool-info) tnx-amount),
        total-nfts-staked: (+ (get total-nfts-staked pool-info) (len nft-ids))
      })
    )
    
    ;; Update pool stats
    (update-pool-participant-count pool-id true)
    
    (ok true)
  )
)

;; Claim rewards from staking
(define-public (claim-rewards (pool-id uint))
  (let (
    (stake-info (unwrap! (get-user-stake tx-sender pool-id) ERR-NOT-STAKED))
    (pending-rewards (unwrap! (calculate-pending-rewards tx-sender pool-id) ERR-NOT-AUTHORIZED))
  )
    (asserts! (> pending-rewards u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (var-get reward-pool-balance) pending-rewards) ERR-INSUFFICIENT-BALANCE)
    
    ;; Update user stake record
    (map-set user-stakes
      { user: tx-sender, pool-id: pool-id }
      (merge stake-info {
        last-reward-claim: stacks-block-height,
        total-rewards-earned: (+ (get total-rewards-earned stake-info) pending-rewards)
      })
    )
    
    ;; Update reward pool balance
    (var-set reward-pool-balance (- (var-get reward-pool-balance) pending-rewards))
    
    ;; Transfer rewards to user (simplified)
    ;; In practice: (try! (as-contract (contract-call? .tnx-token transfer pending-rewards tx-sender (as-contract tx-sender) none)))
    
    ;; Update pool stats
    (update-rewards-distributed pool-id pending-rewards)
    
    (ok pending-rewards)
  )
)

;; Unstake from pool
(define-public (unstake-from-pool (pool-id uint))
  (let (
    (stake-info (unwrap! (get-user-stake tx-sender pool-id) ERR-NOT-STAKED))
    (pool-info (unwrap! (get-pool-info pool-id) ERR-POOL-NOT-FOUND))
    (stake-duration (- stacks-block-height (get stake-timestamp stake-info)))
    (is-early-withdrawal (< stake-duration (var-get minimum-stake-period)))
    (penalty-amount (if is-early-withdrawal 
                      (/ (* (get tnx-amount stake-info) (var-get early-withdrawal-penalty)) u10000)
                      u0))
    (return-amount (- (get tnx-amount stake-info) penalty-amount))
  )
    ;; Claim any pending rewards first
    (try! (claim-rewards pool-id))
    
    ;; Remove staked NFTs from records
    (map remove-nft-records (get nft-ids stake-info))
    
    ;; Remove user stake
    (map-delete user-stakes { user: tx-sender, pool-id: pool-id })
    
    ;; Update pool totals
    (map-set pools
      { pool-id: pool-id }
      (merge pool-info {
        total-tnx-staked: (- (get total-tnx-staked pool-info) (get tnx-amount stake-info)),
        total-nfts-staked: (- (get total-nfts-staked pool-info) (len (get nft-ids stake-info)))
      })
    )
    
    ;; Update pool stats
    (update-pool-participant-count pool-id false)
    
    ;; Transfer tokens back to user (minus penalty if applicable)
    ;; In practice: (try! (as-contract (contract-call? .tnx-token transfer return-amount (as-contract tx-sender) tx-sender none)))
    
    ;; Add penalty to reward pool if early withdrawal
    (if is-early-withdrawal
      (var-set reward-pool-balance (+ (var-get reward-pool-balance) penalty-amount))
      true
    )
    
    (ok { returned-amount: return-amount, penalty: penalty-amount })
  )
)

;; Admin function to add rewards to the pool
(define-public (add-rewards (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; In practice: (try! (contract-call? .tnx-token transfer amount tx-sender (as-contract tx-sender) none))
    
    (var-set reward-pool-balance (+ (var-get reward-pool-balance) amount))
    (ok true)
  )
)

;; Admin function to update reward rate
(define-public (set-reward-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set reward-rate new-rate)
    (ok true)
  )
)

;; Admin function to toggle pool status
(define-public (toggle-pool-status (pool-id uint))
  (let (
    (pool-info (unwrap! (get-pool-info pool-id) ERR-POOL-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    
    (map-set pools
      { pool-id: pool-id }
      (merge pool-info { is-active: (not (get is-active pool-info)) })
    )
    (ok true)
  )
)

;; Private functions

;; Validate NFT ownership (simplified implementation)
(define-private (validate-nft-ownership (nft-ids (list 10 uint)))
  ;; In practice, this would check actual NFT contract ownership
  ;; For now, we'll assume validation passes
  true
)

;; Helper function to record staked NFT
(define-private (stake-nft-records (nft-id uint))
  (map-set staked-nfts
    { nft-id: nft-id }
    {
      owner: tx-sender,
      pool-id: u1, ;; This should be passed as parameter in real implementation
      stake-timestamp: stacks-block-height
    }
  )
)

;; Helper function to remove staked NFT record
(define-private (remove-nft-records (nft-id uint))
  (map-delete staked-nfts { nft-id: nft-id })
)

;; Update pool participant count
(define-private (update-pool-participant-count (pool-id uint) (is-joining bool))
  (let (
    (current-stats (default-to 
      { total-participants: u0, total-rewards-distributed: u0, average-stake-duration: u0 }
      (map-get? pool-stats { pool-id: pool-id })))
  )
    (map-set pool-stats
      { pool-id: pool-id }
      (merge current-stats {
        total-participants: (if is-joining 
                              (+ (get total-participants current-stats) u1)
                              (- (get total-participants current-stats) u1))
      })
    )
  )
)

;; Update rewards distributed
(define-private (update-rewards-distributed (pool-id uint) (amount uint))
  (let (
    (current-stats (default-to 
      { total-participants: u0, total-rewards-distributed: u0, average-stake-duration: u0 }
      (map-get? pool-stats { pool-id: pool-id })))
  )
    (map-set pool-stats
      { pool-id: pool-id }
      (merge current-stats {
        total-rewards-distributed: (+ (get total-rewards-distributed current-stats) amount)
      })
    )
  )
)

;; Get pool statistics
(define-read-only (get-pool-statistics (pool-id uint))
  (map-get? pool-stats { pool-id: pool-id })
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-pools: (var-get total-pools),
    reward-pool-balance: (var-get reward-pool-balance),
    current-reward-rate: (var-get reward-rate),
    early-withdrawal-penalty: (var-get early-withdrawal-penalty)
  }
)