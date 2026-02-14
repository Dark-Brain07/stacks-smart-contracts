;; DeFi Staking Contract
;; Stake STX tokens to earn staking rewards over time
;; Supports flexible staking periods, reward distribution, and compound interest

;; =============================================
;; Constants
;; =============================================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u4001))
(define-constant ERR-INSUFFICIENT-STAKE (err u4002))
(define-constant ERR-NO-STAKE-FOUND (err u4003))
(define-constant ERR-LOCKUP-NOT-EXPIRED (err u4004))
(define-constant ERR-INVALID-AMOUNT (err u4005))
(define-constant ERR-POOL-EMPTY (err u4006))
(define-constant ERR-PAUSED (err u4007))
(define-constant ERR-MAX-STAKERS (err u4008))
(define-constant ERR-ALREADY-STAKING (err u4009))
(define-constant ERR-INVALID-DURATION (err u4010))

;; Staking parameters
(define-constant MIN-STAKE u1000000) ;; 1 STX minimum
(define-constant MAX-STAKERS u10000)
(define-constant REWARD-RATE-PER-BLOCK u100) ;; Base reward rate per block
(define-constant BLOCKS-PER-DAY u144)

;; Lock periods (in blocks)
(define-constant LOCK-FLEXIBLE u0)
(define-constant LOCK-7-DAYS (* BLOCKS-PER-DAY u7))
(define-constant LOCK-30-DAYS (* BLOCKS-PER-DAY u30))
(define-constant LOCK-90-DAYS (* BLOCKS-PER-DAY u90))

;; Multipliers (in basis points, 10000 = 1x)
(define-constant MULTIPLIER-FLEXIBLE u10000)
(define-constant MULTIPLIER-7-DAYS u12500) ;; 1.25x
(define-constant MULTIPLIER-30-DAYS u15000) ;; 1.5x
(define-constant MULTIPLIER-90-DAYS u20000) ;; 2x

;; =============================================
;; Data Variables
;; =============================================

(define-data-var total-staked uint u0)
(define-data-var total-rewards-distributed uint u0)
(define-data-var staker-count uint u0)
(define-data-var reward-pool uint u0)
(define-data-var contract-paused bool false)
(define-data-var emergency-mode bool false)

;; =============================================
;; Data Maps
;; =============================================

;; Individual stake positions
(define-map stakes
  principal
  {
    amount: uint,
    start-block: uint,
    lock-period: uint,
    last-claim-block: uint,
    total-rewards-claimed: uint,
    multiplier: uint
  }
)

;; Staking history
(define-map staking-history
  { staker: principal, action-id: uint }
  {
    action: (string-ascii 16),
    amount: uint,
    block: uint,
    rewards: uint
  }
)

(define-map action-counters principal uint)

;; =============================================
;; Private Helper Functions
;; =============================================

(define-private (get-multiplier-for-lock (lock-period uint))
  (if (is-eq lock-period LOCK-90-DAYS)
    MULTIPLIER-90-DAYS
    (if (is-eq lock-period LOCK-30-DAYS)
      MULTIPLIER-30-DAYS
      (if (is-eq lock-period LOCK-7-DAYS)
        MULTIPLIER-7-DAYS
        MULTIPLIER-FLEXIBLE
      )
    )
  )
)

(define-private (calculate-rewards (staker principal))
  (match (map-get? stakes staker)
    stake-info
      (let (
        (blocks-elapsed (- block-height (get last-claim-block stake-info)))
        (base-reward (* (* (get amount stake-info) REWARD-RATE-PER-BLOCK) blocks-elapsed))
        (multiplied-reward (/ (* base-reward (get multiplier stake-info)) u10000))
        (final-reward (/ multiplied-reward u1000000))
      )
        final-reward
      )
    u0
  )
)

;; =============================================
;; Staking Functions
;; =============================================

;; Stake STX with a lock period
(define-public (stake (amount uint) (lock-period uint))
  (begin
    (asserts! (not (var-get contract-paused)) ERR-PAUSED)
    (asserts! (>= amount MIN-STAKE) ERR-INVALID-AMOUNT)
    (asserts! (is-none (map-get? stakes tx-sender)) ERR-ALREADY-STAKING)
    (asserts! (< (var-get staker-count) MAX-STAKERS) ERR-MAX-STAKERS)
    (asserts! (or
      (is-eq lock-period LOCK-FLEXIBLE)
      (is-eq lock-period LOCK-7-DAYS)
      (is-eq lock-period LOCK-30-DAYS)
      (is-eq lock-period LOCK-90-DAYS)
    ) ERR-INVALID-DURATION)
    ;; Transfer STX to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    ;; Create stake position
    (map-set stakes tx-sender {
      amount: amount,
      start-block: block-height,
      lock-period: lock-period,
      last-claim-block: block-height,
      total-rewards-claimed: u0,
      multiplier: (get-multiplier-for-lock lock-period)
    })
    ;; Update globals
    (var-set total-staked (+ (var-get total-staked) amount))
    (var-set staker-count (+ (var-get staker-count) u1))
    ;; Record history
    (let ((action-id (default-to u0 (map-get? action-counters tx-sender))))
      (map-set staking-history { staker: tx-sender, action-id: action-id }
        { action: "stake", amount: amount, block: block-height, rewards: u0 })
      (map-set action-counters tx-sender (+ action-id u1))
    )
    (print { type: "staked", staker: tx-sender, amount: amount, lock-period: lock-period })
    (ok true)
  )
)

;; Claim accumulated rewards
(define-public (claim-rewards)
  (let (
    (stake-info (unwrap! (map-get? stakes tx-sender) ERR-NO-STAKE-FOUND))
    (rewards (calculate-rewards tx-sender))
  )
    (asserts! (not (var-get contract-paused)) ERR-PAUSED)
    (asserts! (> rewards u0) ERR-POOL-EMPTY)
    ;; Transfer rewards from contract
    (try! (as-contract (stx-transfer? rewards tx-sender tx-sender)))
    ;; Update stake info
    (map-set stakes tx-sender (merge stake-info {
      last-claim-block: block-height,
      total-rewards-claimed: (+ (get total-rewards-claimed stake-info) rewards)
    }))
    (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) rewards))
    ;; Record history
    (let ((action-id (default-to u0 (map-get? action-counters tx-sender))))
      (map-set staking-history { staker: tx-sender, action-id: action-id }
        { action: "claim", amount: u0, block: block-height, rewards: rewards })
      (map-set action-counters tx-sender (+ action-id u1))
    )
    (print { type: "rewards-claimed", staker: tx-sender, rewards: rewards })
    (ok rewards)
  )
)

;; Unstake tokens
(define-public (unstake)
  (let (
    (stake-info (unwrap! (map-get? stakes tx-sender) ERR-NO-STAKE-FOUND))
    (amount (get amount stake-info))
    (lock-end (+ (get start-block stake-info) (get lock-period stake-info)))
    (pending-rewards (calculate-rewards tx-sender))
    (total-return (+ amount pending-rewards))
  )
    (asserts! (not (var-get contract-paused)) ERR-PAUSED)
    ;; Check lock period (skip in emergency mode)
    (asserts! (or (var-get emergency-mode) (>= block-height lock-end)) ERR-LOCKUP-NOT-EXPIRED)
    ;; Transfer tokens + rewards back
    (try! (as-contract (stx-transfer? total-return tx-sender tx-sender)))
    ;; Clean up
    (map-delete stakes tx-sender)
    (var-set total-staked (- (var-get total-staked) amount))
    (var-set staker-count (- (var-get staker-count) u1))
    (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) pending-rewards))
    ;; Record history
    (let ((action-id (default-to u0 (map-get? action-counters tx-sender))))
      (map-set staking-history { staker: tx-sender, action-id: action-id }
        { action: "unstake", amount: amount, block: block-height, rewards: pending-rewards })
      (map-set action-counters tx-sender (+ action-id u1))
    )
    (print { type: "unstaked", staker: tx-sender, amount: amount, rewards: pending-rewards })
    (ok total-return)
  )
)

;; =============================================
;; Admin Functions
;; =============================================

;; Fund the reward pool
(define-public (fund-rewards (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set reward-pool (+ (var-get reward-pool) amount))
    (print { type: "rewards-funded", funder: tx-sender, amount: amount })
    (ok true)
  )
)

(define-public (pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)

(define-public (set-emergency-mode (enabled bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set emergency-mode enabled)
    (print { type: "emergency-mode", enabled: enabled })
    (ok true)
  )
)

;; =============================================
;; Read-Only Functions
;; =============================================

(define-read-only (get-stake-info (staker principal))
  (ok (map-get? stakes staker))
)

(define-read-only (get-pending-rewards (staker principal))
  (ok (calculate-rewards staker))
)

(define-read-only (get-total-staked)
  (ok (var-get total-staked))
)

(define-read-only (get-staker-count)
  (ok (var-get staker-count))
)

(define-read-only (get-total-rewards-distributed)
  (ok (var-get total-rewards-distributed))
)

(define-read-only (get-reward-pool)
  (ok (var-get reward-pool))
)

(define-read-only (get-min-stake)
  (ok MIN-STAKE)
)

(define-read-only (get-lock-multipliers)
  (ok {
    flexible: MULTIPLIER-FLEXIBLE,
    seven-days: MULTIPLIER-7-DAYS,
    thirty-days: MULTIPLIER-30-DAYS,
    ninety-days: MULTIPLIER-90-DAYS
  })
)

(define-read-only (is-staking (account principal))
  (is-some (map-get? stakes account))
)

(define-read-only (get-contract-status)
  (ok {
    paused: (var-get contract-paused),
    emergency: (var-get emergency-mode),
    total-staked: (var-get total-staked),
    staker-count: (var-get staker-count),
    reward-pool: (var-get reward-pool)
  })
)
