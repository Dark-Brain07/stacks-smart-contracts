;; SIP-010 Fungible Token - StacksToken (STKN)
;; A fully compliant SIP-010 fungible token with minting, burning, and transfer capabilities
;; Implements the standard fungible token trait for the Stacks blockchain

;; =============================================
;; Constants
;; =============================================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u1001))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1002))
(define-constant ERR-INVALID-AMOUNT (err u1003))
(define-constant ERR-TRANSFER-FAILED (err u1004))
(define-constant ERR-MINT-FAILED (err u1005))
(define-constant ERR-BURN-FAILED (err u1006))
(define-constant ERR-PAUSED (err u1007))

(define-constant TOKEN-NAME "StacksToken")
(define-constant TOKEN-SYMBOL "STKN")
(define-constant TOKEN-DECIMALS u6)
(define-constant MAX-SUPPLY u1000000000000000) ;; 1 billion tokens with 6 decimals
(define-constant INITIAL-SUPPLY u100000000000000) ;; 100 million tokens with 6 decimals

;; =============================================
;; Data Variables
;; =============================================

(define-fungible-token stacks-token MAX-SUPPLY)

(define-data-var token-uri (optional (string-utf8 256)) (some u"https://stacks-smart-contracts.io/token/stkn.json"))
(define-data-var contract-paused bool false)
(define-data-var total-minted uint u0)
(define-data-var total-burned uint u0)

;; =============================================
;; Data Maps
;; =============================================

(define-map allowances
  { owner: principal, spender: principal }
  { amount: uint }
)

(define-map minters principal bool)

;; =============================================
;; Authorization Checks
;; =============================================

(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-minter (account principal))
  (default-to false (map-get? minters account))
)

(define-private (check-not-paused)
  (not (var-get contract-paused))
)

;; =============================================
;; SIP-010 Trait Implementation
;; =============================================

;; Transfer tokens from sender to recipient
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (check-not-paused) ERR-PAUSED)
    (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (match (ft-transfer? stacks-token amount sender recipient)
      success (begin
        (match memo to-print (print to-print) 0x)
        (print { type: "transfer", sender: sender, recipient: recipient, amount: amount })
        (ok true)
      )
      error ERR-TRANSFER-FAILED
    )
  )
)

;; Get token name
(define-read-only (get-name)
  (ok TOKEN-NAME)
)

;; Get token symbol
(define-read-only (get-symbol)
  (ok TOKEN-SYMBOL)
)

;; Get token decimals
(define-read-only (get-decimals)
  (ok TOKEN-DECIMALS)
)

;; Get balance of an account
(define-read-only (get-balance (account principal))
  (ok (ft-get-balance stacks-token account))
)

;; Get total supply
(define-read-only (get-total-supply)
  (ok (ft-get-supply stacks-token))
)

;; Get token URI for metadata
(define-read-only (get-token-uri)
  (ok (var-get token-uri))
)

;; =============================================
;; Minting Functions
;; =============================================

;; Mint new tokens (only owner or authorized minters)
(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (check-not-paused) ERR-PAUSED)
    (asserts! (or (is-contract-owner) (is-minter tx-sender)) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (match (ft-mint? stacks-token amount recipient)
      success (begin
        (var-set total-minted (+ (var-get total-minted) amount))
        (print { type: "mint", recipient: recipient, amount: amount })
        (ok true)
      )
      error ERR-MINT-FAILED
    )
  )
)

;; =============================================
;; Burning Functions
;; =============================================

;; Burn tokens from sender's balance
(define-public (burn (amount uint))
  (begin
    (asserts! (check-not-paused) ERR-PAUSED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (match (ft-burn? stacks-token amount tx-sender)
      success (begin
        (var-set total-burned (+ (var-get total-burned) amount))
        (print { type: "burn", burner: tx-sender, amount: amount })
        (ok true)
      )
      error ERR-BURN-FAILED
    )
  )
)

;; =============================================
;; Allowance Functions
;; =============================================

;; Approve spender to transfer tokens on behalf of owner
(define-public (approve (spender principal) (amount uint))
  (begin
    (asserts! (check-not-paused) ERR-PAUSED)
    (map-set allowances { owner: tx-sender, spender: spender } { amount: amount })
    (print { type: "approval", owner: tx-sender, spender: spender, amount: amount })
    (ok true)
  )
)

;; Get allowance for a spender
(define-read-only (get-allowance (owner principal) (spender principal))
  (ok (default-to u0 (get amount (map-get? allowances { owner: owner, spender: spender }))))
)

;; Transfer tokens using allowance
(define-public (transfer-from (amount uint) (owner principal) (recipient principal))
  (let (
    (current-allowance (default-to u0 (get amount (map-get? allowances { owner: owner, spender: tx-sender }))))
  )
    (asserts! (check-not-paused) ERR-PAUSED)
    (asserts! (>= current-allowance amount) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (match (ft-transfer? stacks-token amount owner recipient)
      success (begin
        (map-set allowances { owner: owner, spender: tx-sender } { amount: (- current-allowance amount) })
        (print { type: "transfer-from", owner: owner, spender: tx-sender, recipient: recipient, amount: amount })
        (ok true)
      )
      error ERR-TRANSFER-FAILED
    )
  )
)

;; =============================================
;; Admin Functions
;; =============================================

;; Add minter
(define-public (add-minter (minter principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-set minters minter true)
    (print { type: "minter-added", minter: minter })
    (ok true)
  )
)

;; Remove minter
(define-public (remove-minter (minter principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-delete minters minter)
    (print { type: "minter-removed", minter: minter })
    (ok true)
  )
)

;; Pause contract
(define-public (pause)
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-paused true)
    (print { type: "paused" })
    (ok true)
  )
)

;; Unpause contract
(define-public (unpause)
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-paused false)
    (print { type: "unpaused" })
    (ok true)
  )
)

;; Update token URI
(define-public (set-token-uri (new-uri (optional (string-utf8 256))))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set token-uri new-uri)
    (print { type: "uri-updated", uri: new-uri })
    (ok true)
  )
)

;; =============================================
;; Read-Only Utility Functions
;; =============================================

(define-read-only (get-total-minted)
  (ok (var-get total-minted))
)

(define-read-only (get-total-burned)
  (ok (var-get total-burned))
)

(define-read-only (is-paused)
  (ok (var-get contract-paused))
)

(define-read-only (get-contract-owner)
  (ok CONTRACT-OWNER)
)

;; =============================================
;; Initialization - Mint initial supply to deployer
;; =============================================

(ft-mint? stacks-token INITIAL-SUPPLY CONTRACT-OWNER)
