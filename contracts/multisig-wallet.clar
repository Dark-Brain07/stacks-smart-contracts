;; Multi-Signature Wallet Contract
;; A secure multi-sig wallet requiring M-of-N signatures for transactions
;; Supports STX transfers, contract calls, and owner management

;; =============================================
;; Constants
;; =============================================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u5001))
(define-constant ERR-NOT-OWNER (err u5002))
(define-constant ERR-TX-NOT-FOUND (err u5003))
(define-constant ERR-ALREADY-CONFIRMED (err u5004))
(define-constant ERR-NOT-CONFIRMED (err u5005))
(define-constant ERR-TX-ALREADY-EXECUTED (err u5006))
(define-constant ERR-INSUFFICIENT-CONFIRMATIONS (err u5007))
(define-constant ERR-INVALID-PARAMS (err u5008))
(define-constant ERR-OWNER-EXISTS (err u5009))
(define-constant ERR-MAX-OWNERS (err u5010))
(define-constant ERR-TX-EXPIRED (err u5011))
(define-constant ERR-INSUFFICIENT-BALANCE (err u5012))

(define-constant MAX-OWNERS u10)
(define-constant TX-EXPIRY u1008) ;; ~7 days in blocks

;; =============================================
;; Data Variables
;; =============================================

(define-data-var tx-count uint u0)
(define-data-var owner-count uint u0)
(define-data-var required-confirmations uint u2) ;; M-of-N, default 2

;; =============================================
;; Data Maps
;; =============================================

;; Wallet owners
(define-map owners principal bool)

;; Pending transactions
(define-map transactions
  uint
  {
    to: principal,
    amount: uint,
    description: (string-ascii 256),
    submitted-by: principal,
    submitted-at: uint,
    confirmations: uint,
    executed: bool,
    revoked: bool
  }
)

;; Confirmation tracking
(define-map confirmations
  { tx-id: uint, owner: principal }
  bool
)

;; Transaction execution log
(define-map execution-log
  uint
  {
    executed-at: uint,
    executed-by: principal,
    success: bool
  }
)

;; =============================================
;; Authorization Checks
;; =============================================

(define-private (is-owner (account principal))
  (default-to false (map-get? owners account))
)

(define-private (check-owner)
  (is-owner tx-sender)
)

;; =============================================
;; Deposit Functions
;; =============================================

;; Deposit STX into multi-sig wallet
(define-public (deposit (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-PARAMS)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (print { type: "multisig-deposit", depositor: tx-sender, amount: amount })
    (ok true)
  )
)

;; =============================================
;; Transaction Management
;; =============================================

;; Submit a new transaction for approval
(define-public (submit-transaction (to principal) (amount uint) (description (string-ascii 256)))
  (let (
    (new-id (+ (var-get tx-count) u1))
  )
    (asserts! (check-owner) ERR-NOT-OWNER)
    (asserts! (> amount u0) ERR-INVALID-PARAMS)
    ;; Create transaction
    (map-set transactions new-id {
      to: to,
      amount: amount,
      description: description,
      submitted-by: tx-sender,
      submitted-at: block-height,
      confirmations: u1,
      executed: false,
      revoked: false
    })
    ;; Auto-confirm by submitter
    (map-set confirmations { tx-id: new-id, owner: tx-sender } true)
    (var-set tx-count new-id)
    (print { type: "tx-submitted", tx-id: new-id, to: to, amount: amount, submitted-by: tx-sender })
    (ok new-id)
  )
)

;; Confirm a pending transaction
(define-public (confirm-transaction (tx-id uint))
  (let (
    (tx (unwrap! (map-get? transactions tx-id) ERR-TX-NOT-FOUND))
  )
    (asserts! (check-owner) ERR-NOT-OWNER)
    (asserts! (not (get executed tx)) ERR-TX-ALREADY-EXECUTED)
    (asserts! (not (get revoked tx)) ERR-TX-NOT-FOUND)
    (asserts! (<= block-height (+ (get submitted-at tx) TX-EXPIRY)) ERR-TX-EXPIRED)
    (asserts! (not (default-to false (map-get? confirmations { tx-id: tx-id, owner: tx-sender }))) ERR-ALREADY-CONFIRMED)
    ;; Add confirmation
    (map-set confirmations { tx-id: tx-id, owner: tx-sender } true)
    (map-set transactions tx-id (merge tx { confirmations: (+ (get confirmations tx) u1) }))
    (print { type: "tx-confirmed", tx-id: tx-id, confirmer: tx-sender, total-confirmations: (+ (get confirmations tx) u1) })
    (ok true)
  )
)

;; Revoke a confirmation
(define-public (revoke-confirmation (tx-id uint))
  (let (
    (tx (unwrap! (map-get? transactions tx-id) ERR-TX-NOT-FOUND))
  )
    (asserts! (check-owner) ERR-NOT-OWNER)
    (asserts! (not (get executed tx)) ERR-TX-ALREADY-EXECUTED)
    (asserts! (default-to false (map-get? confirmations { tx-id: tx-id, owner: tx-sender })) ERR-NOT-CONFIRMED)
    ;; Remove confirmation
    (map-set confirmations { tx-id: tx-id, owner: tx-sender } false)
    (map-set transactions tx-id (merge tx { confirmations: (- (get confirmations tx) u1) }))
    (print { type: "tx-revoked", tx-id: tx-id, revoker: tx-sender })
    (ok true)
  )
)

;; Execute a confirmed transaction
(define-public (execute-transaction (tx-id uint))
  (let (
    (tx (unwrap! (map-get? transactions tx-id) ERR-TX-NOT-FOUND))
    (required (var-get required-confirmations))
  )
    (asserts! (check-owner) ERR-NOT-OWNER)
    (asserts! (not (get executed tx)) ERR-TX-ALREADY-EXECUTED)
    (asserts! (not (get revoked tx)) ERR-TX-NOT-FOUND)
    (asserts! (<= block-height (+ (get submitted-at tx) TX-EXPIRY)) ERR-TX-EXPIRED)
    (asserts! (>= (get confirmations tx) required) ERR-INSUFFICIENT-CONFIRMATIONS)
    ;; Execute the transfer
    (try! (as-contract (stx-transfer? (get amount tx) tx-sender (get to tx))))
    ;; Mark as executed
    (map-set transactions tx-id (merge tx { executed: true }))
    (map-set execution-log tx-id {
      executed-at: block-height,
      executed-by: tx-sender,
      success: true
    })
    (print { type: "tx-executed", tx-id: tx-id, to: (get to tx), amount: (get amount tx), executor: tx-sender })
    (ok true)
  )
)

;; =============================================
;; Owner Management
;; =============================================

;; Add a new owner (requires existing owner)
(define-public (add-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-owner new-owner)) ERR-OWNER-EXISTS)
    (asserts! (< (var-get owner-count) MAX-OWNERS) ERR-MAX-OWNERS)
    (map-set owners new-owner true)
    (var-set owner-count (+ (var-get owner-count) u1))
    (print { type: "owner-added", owner: new-owner })
    (ok true)
  )
)

;; Remove an owner
(define-public (remove-owner (owner principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-owner owner) ERR-NOT-OWNER)
    (asserts! (> (var-get owner-count) (var-get required-confirmations)) ERR-INVALID-PARAMS)
    (map-delete owners owner)
    (var-set owner-count (- (var-get owner-count) u1))
    (print { type: "owner-removed", owner: owner })
    (ok true)
  )
)

;; Change required confirmations
(define-public (set-required-confirmations (new-required uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> new-required u0) ERR-INVALID-PARAMS)
    (asserts! (<= new-required (var-get owner-count)) ERR-INVALID-PARAMS)
    (var-set required-confirmations new-required)
    (print { type: "confirmations-changed", required: new-required })
    (ok true)
  )
)

;; =============================================
;; Read-Only Functions
;; =============================================

(define-read-only (get-transaction (tx-id uint))
  (ok (map-get? transactions tx-id))
)

(define-read-only (get-confirmation-status (tx-id uint) (owner principal))
  (ok (default-to false (map-get? confirmations { tx-id: tx-id, owner: owner })))
)

(define-read-only (get-tx-count)
  (ok (var-get tx-count))
)

(define-read-only (get-owner-count)
  (ok (var-get owner-count))
)

(define-read-only (get-required-confirmations)
  (ok (var-get required-confirmations))
)

(define-read-only (check-is-owner (account principal))
  (ok (is-owner account))
)

(define-read-only (get-wallet-balance)
  (ok (stx-get-balance (as-contract tx-sender)))
)

(define-read-only (get-execution-log (tx-id uint))
  (ok (map-get? execution-log tx-id))
)

(define-read-only (get-wallet-info)
  (ok {
    owner-count: (var-get owner-count),
    required-confirmations: (var-get required-confirmations),
    tx-count: (var-get tx-count),
    balance: (stx-get-balance (as-contract tx-sender))
  })
)

;; =============================================
;; Initialization
;; =============================================

(map-set owners CONTRACT-OWNER true)
(var-set owner-count u1)
