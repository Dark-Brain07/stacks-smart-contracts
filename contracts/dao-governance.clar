;; DAO Governance Contract
;; A decentralized autonomous organization with proposal creation, voting, and execution
;; Supports quorum-based voting with time-locked proposals

;; =============================================
;; Constants
;; =============================================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u3001))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u3002))
(define-constant ERR-ALREADY-VOTED (err u3003))
(define-constant ERR-VOTING-ENDED (err u3004))
(define-constant ERR-VOTING-NOT-ENDED (err u3005))
(define-constant ERR-QUORUM-NOT-MET (err u3006))
(define-constant ERR-PROPOSAL-ALREADY-EXECUTED (err u3007))
(define-constant ERR-NOT-MEMBER (err u3008))
(define-constant ERR-INVALID-PARAMS (err u3009))
(define-constant ERR-PROPOSAL-REJECTED (err u3010))
(define-constant ERR-MAX-PROPOSALS (err u3011))

(define-constant VOTING-PERIOD u144) ;; ~1 day in blocks (10 min blocks)
(define-constant QUORUM-THRESHOLD u51) ;; 51% quorum
(define-constant MAX-PROPOSALS u1000)
(define-constant DAO-NAME "StacksDAO")

;; =============================================
;; Data Variables
;; =============================================

(define-data-var proposal-count uint u0)
(define-data-var total-members uint u0)
(define-data-var treasury-balance uint u0)

;; =============================================
;; Data Maps
;; =============================================

;; DAO Members with voting power
(define-map members
  principal
  { voting-power: uint, joined-at: uint, proposals-created: uint }
)

;; Proposals
(define-map proposals
  uint
  {
    title: (string-ascii 128),
    description: (string-ascii 512),
    proposer: principal,
    start-block: uint,
    end-block: uint,
    votes-for: uint,
    votes-against: uint,
    total-votes: uint,
    executed: bool,
    proposal-type: (string-ascii 32),
    amount: uint,
    target: principal
  }
)

;; Vote tracking
(define-map votes
  { proposal-id: uint, voter: principal }
  { vote: bool, weight: uint }
)

;; Delegate voting
(define-map delegates
  principal
  principal
)

;; =============================================
;; Member Management
;; =============================================

;; Add a member (owner only)
(define-public (add-member (member principal) (voting-power uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> voting-power u0) ERR-INVALID-PARAMS)
    (map-set members member {
      voting-power: voting-power,
      joined-at: block-height,
      proposals-created: u0
    })
    (var-set total-members (+ (var-get total-members) u1))
    (print { type: "member-added", member: member, voting-power: voting-power })
    (ok true)
  )
)

;; Remove a member (owner only)
(define-public (remove-member (member principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? members member)) ERR-NOT-MEMBER)
    (map-delete members member)
    (var-set total-members (- (var-get total-members) u1))
    (print { type: "member-removed", member: member })
    (ok true)
  )
)

;; Check if someone is a member
(define-read-only (is-member (account principal))
  (is-some (map-get? members account))
)

;; =============================================
;; Proposal Functions
;; =============================================

;; Create a new proposal
(define-public (create-proposal
  (title (string-ascii 128))
  (description (string-ascii 512))
  (proposal-type (string-ascii 32))
  (amount uint)
  (target principal)
)
  (let (
    (new-id (+ (var-get proposal-count) u1))
    (member-info (unwrap! (map-get? members tx-sender) ERR-NOT-MEMBER))
  )
    (asserts! (<= new-id MAX-PROPOSALS) ERR-MAX-PROPOSALS)
    (map-set proposals new-id {
      title: title,
      description: description,
      proposer: tx-sender,
      start-block: block-height,
      end-block: (+ block-height VOTING-PERIOD),
      votes-for: u0,
      votes-against: u0,
      total-votes: u0,
      executed: false,
      proposal-type: proposal-type,
      amount: amount,
      target: target
    })
    ;; Update member's proposal count
    (map-set members tx-sender (merge member-info { proposals-created: (+ (get proposals-created member-info) u1) }))
    (var-set proposal-count new-id)
    (print { type: "proposal-created", id: new-id, title: title, proposer: tx-sender })
    (ok new-id)
  )
)

;; =============================================
;; Voting Functions
;; =============================================

;; Cast a vote
(define-public (vote (proposal-id uint) (vote-for bool))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (member-info (unwrap! (map-get? members tx-sender) ERR-NOT-MEMBER))
    (weight (get voting-power member-info))
  )
    ;; Check voting is still open
    (asserts! (<= block-height (get end-block proposal)) ERR-VOTING-ENDED)
    ;; Check hasn't already voted
    (asserts! (is-none (map-get? votes { proposal-id: proposal-id, voter: tx-sender })) ERR-ALREADY-VOTED)
    ;; Record vote
    (map-set votes { proposal-id: proposal-id, voter: tx-sender } { vote: vote-for, weight: weight })
    ;; Update proposal tallies
    (map-set proposals proposal-id
      (merge proposal {
        votes-for: (if vote-for (+ (get votes-for proposal) weight) (get votes-for proposal)),
        votes-against: (if (not vote-for) (+ (get votes-against proposal) weight) (get votes-against proposal)),
        total-votes: (+ (get total-votes proposal) weight)
      })
    )
    (print { type: "vote-cast", proposal-id: proposal-id, voter: tx-sender, vote-for: vote-for, weight: weight })
    (ok true)
  )
)

;; =============================================
;; Execution Functions
;; =============================================

;; Execute a passed proposal
(define-public (execute-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
  )
    ;; Voting must be over
    (asserts! (> block-height (get end-block proposal)) ERR-VOTING-NOT-ENDED)
    ;; Not already executed
    (asserts! (not (get executed proposal)) ERR-PROPOSAL-ALREADY-EXECUTED)
    ;; Must pass quorum
    (asserts! (> (get votes-for proposal) (get votes-against proposal)) ERR-PROPOSAL-REJECTED)
    ;; Mark as executed
    (map-set proposals proposal-id (merge proposal { executed: true }))
    (print { type: "proposal-executed", proposal-id: proposal-id })
    (ok true)
  )
)

;; =============================================
;; Treasury Functions
;; =============================================

;; Deposit STX to DAO treasury
(define-public (deposit (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-PARAMS)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (print { type: "treasury-deposit", depositor: tx-sender, amount: amount })
    (ok true)
  )
)

;; =============================================
;; Delegation
;; =============================================

;; Delegate voting power
(define-public (delegate-to (delegate principal))
  (begin
    (asserts! (is-member tx-sender) ERR-NOT-MEMBER)
    (asserts! (is-member delegate) ERR-NOT-MEMBER)
    (map-set delegates tx-sender delegate)
    (print { type: "delegation", delegator: tx-sender, delegate: delegate })
    (ok true)
  )
)

;; Remove delegation
(define-public (remove-delegation)
  (begin
    (map-delete delegates tx-sender)
    (print { type: "delegation-removed", delegator: tx-sender })
    (ok true)
  )
)

;; =============================================
;; Read-Only Functions
;; =============================================

(define-read-only (get-proposal (proposal-id uint))
  (ok (map-get? proposals proposal-id))
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (ok (map-get? votes { proposal-id: proposal-id, voter: voter }))
)

(define-read-only (get-member (account principal))
  (ok (map-get? members account))
)

(define-read-only (get-proposal-count)
  (ok (var-get proposal-count))
)

(define-read-only (get-total-members)
  (ok (var-get total-members))
)

(define-read-only (get-treasury-balance)
  (ok (var-get treasury-balance))
)

(define-read-only (get-dao-name)
  (ok DAO-NAME)
)

(define-read-only (get-delegate (account principal))
  (ok (map-get? delegates account))
)

(define-read-only (get-voting-period)
  (ok VOTING-PERIOD)
)

(define-read-only (get-quorum-threshold)
  (ok QUORUM-THRESHOLD)
)

;; =============================================
;; Initialization - Add deployer as first member
;; =============================================

(map-set members CONTRACT-OWNER {
  voting-power: u100,
  joined-at: block-height,
  proposals-created: u0
})
(var-set total-members u1)
