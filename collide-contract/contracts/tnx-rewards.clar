;; TNX Token Rewards Smart Contract
;; Handles token distribution for gaming achievements

;; Define the TNX token (SIP-010 Fungible Token)
(define-fungible-token tnx-token)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-player (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-challenge (err u103))
(define-constant err-already-completed (err u104))
(define-constant err-invalid-ranking (err u105))

;; Data Variables
(define-data-var total-supply uint u0)
(define-data-var challenge-base-reward uint u100) ;; Base TNX for challenges
(define-data-var collision-base-reward uint u150) ;; Base TNX for collision events
(define-data-var milestone-base-reward uint u200) ;; Base TNX for milestones

;; Data Maps
(define-map player-stats principal {
    total-earned: uint,
    challenges-completed: uint,
    collision-wins: uint,
    milestones-achieved: uint,
    current-ranking: uint
})

(define-map challenge-rewards uint {
    name: (string-ascii 50),
    base-reward: uint,
    difficulty-multiplier: uint,
    active: bool
})

(define-map collision-event-rewards uint {
    name: (string-ascii 50),
    base-reward: uint,
    ranking-multipliers: (list 10 uint), ;; Top 10 ranking multipliers
    active: bool
})

(define-map milestone-rewards uint {
    name: (string-ascii 50),
    requirement: uint,
    reward-amount: uint,
    active: bool
})

(define-map player-challenge-completion principal (list 100 uint))
(define-map player-milestone-completion principal (list 50 uint))

;; Read-only functions
(define-read-only (get-balance (player principal))
    (ft-get-balance tnx-token player)
)

(define-read-only (get-total-supply)
    (ft-get-supply tnx-token)
)

(define-read-only (get-player-stats (player principal))
    (map-get? player-stats player)
)

(define-read-only (get-challenge-info (challenge-id uint))
    (map-get? challenge-rewards challenge-id)
)

(define-read-only (get-collision-event-info (event-id uint))
    (map-get? collision-event-rewards event-id)
)

(define-read-only (get-milestone-info (milestone-id uint))
    (map-get? milestone-rewards milestone-id)
)

;; Private functions
(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner)
)

(define-private (calculate-challenge-reward (base-reward uint) (difficulty-multiplier uint) (player-ranking uint))
    (let ((base-calculation (* base-reward difficulty-multiplier)))
        (if (<= player-ranking u3)
            (* base-calculation u2) ;; Double reward for top 3
            (if (<= player-ranking u10)
                (+ base-calculation (/ base-calculation u2)) ;; 1.5x for top 10
                base-calculation ;; Base reward for others
            )
        )
    )
)

(define-private (calculate-collision-reward (base-reward uint) (ranking uint) (multipliers (list 10 uint)))
    (let ((multiplier (default-to u1 (element-at multipliers (- ranking u1)))))
        (* base-reward multiplier)
    )
)

(define-private (mint-tokens (recipient principal) (amount uint))
    (begin
        (try! (ft-mint? tnx-token amount recipient))
        (var-set total-supply (+ (var-get total-supply) amount))
        (ok amount)
    )
)

(define-private (update-player-stats (player principal) (earned-amount uint) (stat-type (string-ascii 20)))
    (let ((current-stats (default-to 
            {total-earned: u0, challenges-completed: u0, collision-wins: u0, milestones-achieved: u0, current-ranking: u999}
            (map-get? player-stats player))))
        (map-set player-stats player
            (if (is-eq stat-type "challenge")
                (merge current-stats {
                    total-earned: (+ (get total-earned current-stats) earned-amount),
                    challenges-completed: (+ (get challenges-completed current-stats) u1)
                })
                (if (is-eq stat-type "collision")
                    (merge current-stats {
                        total-earned: (+ (get total-earned current-stats) earned-amount),
                        collision-wins: (+ (get collision-wins current-stats) u1)
                    })
                    (if (is-eq stat-type "milestone")
                        (merge current-stats {
                            total-earned: (+ (get total-earned current-stats) earned-amount),
                            milestones-achieved: (+ (get milestones-achieved current-stats) u1)
                        })
                        current-stats
                    )
                )
            )
        )
    )
)

;; Public functions

;; Initialize contract with initial token supply
(define-public (initialize (initial-supply uint))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (try! (ft-mint? tnx-token initial-supply contract-owner))
        (var-set total-supply initial-supply)
        (ok true)
    )
)

;; Reward player for completing a challenge
(define-public (reward-challenge-completion (player principal) (challenge-id uint) (player-ranking uint))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (let ((challenge-info (unwrap! (map-get? challenge-rewards challenge-id) err-invalid-challenge))
              (completed-challenges (default-to (list) (map-get? player-challenge-completion player))))
            (asserts! (get active challenge-info) err-invalid-challenge)
            (asserts! (is-none (index-of completed-challenges challenge-id)) err-already-completed)
            
            (let ((reward-amount (calculate-challenge-reward 
                    (get base-reward challenge-info) 
                    (get difficulty-multiplier challenge-info) 
                    player-ranking)))
                (try! (mint-tokens player reward-amount))
                (update-player-stats player reward-amount "challenge")
                (map-set player-challenge-completion player 
                    (unwrap! (as-max-len? (append completed-challenges challenge-id) u100) err-invalid-challenge))
                (ok reward-amount)
            )
        )
    )
)

;; Reward player for winning collision event
(define-public (reward-collision-win (player principal) (event-id uint) (final-ranking uint))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (asserts! (and (>= final-ranking u1) (<= final-ranking u10)) err-invalid-ranking)
        
        (let ((event-info (unwrap! (map-get? collision-event-rewards event-id) err-invalid-challenge)))
            (asserts! (get active event-info) err-invalid-challenge)
            
            (let ((reward-amount (calculate-collision-reward 
                    (get base-reward event-info) 
                    final-ranking 
                    (get ranking-multipliers event-info))))
                (try! (mint-tokens player reward-amount))
                (update-player-stats player reward-amount "collision")
                (ok reward-amount)
            )
        )
    )
)

;; Reward player for milestone completion
(define-public (reward-milestone-completion (player principal) (milestone-id uint))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (let ((milestone-info (unwrap! (map-get? milestone-rewards milestone-id) err-invalid-challenge))
              (completed-milestones (default-to (list) (map-get? player-milestone-completion player))))
            (asserts! (get active milestone-info) err-invalid-challenge)
            (asserts! (is-none (index-of completed-milestones milestone-id)) err-already-completed)
            
            (let ((reward-amount (get reward-amount milestone-info)))
                (try! (mint-tokens player reward-amount))
                (update-player-stats player reward-amount "milestone")
                (map-set player-milestone-completion player 
                    (unwrap! (as-max-len? (append completed-milestones milestone-id) u50) err-invalid-challenge))
                (ok reward-amount)
            )
        )
    )
)

;; Admin function to create new challenge
(define-public (create-challenge (challenge-id uint) (name (string-ascii 50)) (base-reward uint) (difficulty-multiplier uint))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (map-set challenge-rewards challenge-id {
            name: name,
            base-reward: base-reward,
            difficulty-multiplier: difficulty-multiplier,
            active: true
        })
        (ok true)
    )
)

;; Admin function to create new collision event
(define-public (create-collision-event (event-id uint) (name (string-ascii 50)) (base-reward uint) (multipliers (list 10 uint)))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (map-set collision-event-rewards event-id {
            name: name,
            base-reward: base-reward,
            ranking-multipliers: multipliers,
            active: true
        })
        (ok true)
    )
)

;; Admin function to create new milestone
(define-public (create-milestone (milestone-id uint) (name (string-ascii 50)) (requirement uint) (reward-amount uint))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (map-set milestone-rewards milestone-id {
            name: name,
            requirement: requirement,
            reward-amount: reward-amount,
            active: true
        })
        (ok true)
    )
)

;; Admin function to update base reward amounts
(define-public (update-base-rewards (challenge-reward uint) (collision-reward uint) (milestone-reward uint))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (var-set challenge-base-reward challenge-reward)
        (var-set collision-base-reward collision-reward)
        (var-set milestone-base-reward milestone-reward)
        (ok true)
    )
)

;; Transfer tokens between players
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
        (asserts! (is-eq tx-sender sender) err-owner-only)
        (ft-transfer? tnx-token amount sender recipient)
    )
)

;; Burn tokens (for game mechanics like upgrades)
(define-public (burn (amount uint) (owner principal))
    (begin
        (asserts! (is-eq tx-sender owner) err-owner-only)
        (ft-burn? tnx-token amount owner)
    )
)