;; SIP-009 Non-Fungible Token - StacksNFT Collection
;; A comprehensive NFT contract with minting, burning, royalties, and metadata
;; Implements the standard SIP-009 non-fungible token trait for the Stacks blockchain

;; =============================================
;; Constants
;; =============================================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u2001))
(define-constant ERR-NOT-FOUND (err u2002))
(define-constant ERR-ALREADY-MINTED (err u2003))
(define-constant ERR-MINT-LIMIT-REACHED (err u2004))
(define-constant ERR-TRANSFER-FAILED (err u2005))
(define-constant ERR-LISTING-NOT-FOUND (err u2006))
(define-constant ERR-WRONG-PRICE (err u2007))
(define-constant ERR-PAUSED (err u2008))
(define-constant ERR-BURN-FAILED (err u2009))
(define-constant ERR-INVALID-ROYALTY (err u2010))

(define-constant COLLECTION-NAME "StacksNFT Collection")
(define-constant COLLECTION-SYMBOL "SNFT")
(define-constant MAX-SUPPLY u10000)
(define-constant MINT-PRICE u1000000) ;; 1 STX
(define-constant ROYALTY-PERCENT u5) ;; 5% royalty on secondary sales

;; =============================================
;; Data Variables
;; =============================================

(define-non-fungible-token stacks-nft uint)

(define-data-var last-token-id uint u0)
(define-data-var base-uri (string-ascii 256) "https://stacks-smart-contracts.io/nft/metadata/")
(define-data-var contract-paused bool false)
(define-data-var mint-enabled bool true)
(define-data-var royalty-address principal CONTRACT-OWNER)

;; =============================================
;; Data Maps
;; =============================================

;; Token metadata
(define-map token-metadata
  uint
  {
    name: (string-ascii 64),
    description: (string-ascii 256),
    attributes: (string-ascii 256),
    minted-at: uint,
    minted-by: principal
  }
)

;; Marketplace listings
(define-map listings
  uint
  { price: uint, seller: principal }
)

;; Token approvals
(define-map token-approvals
  uint
  principal
)

;; Operator approvals (approve all)
(define-map operator-approvals
  { owner: principal, operator: principal }
  bool
)

;; Whitelist for minting
(define-map whitelist
  principal
  { allowed: bool, minted: uint, max-mint: uint }
)

;; =============================================
;; Authorization Checks
;; =============================================

(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-token-owner (token-id uint) (account principal))
  (is-eq (unwrap! (nft-get-owner? stacks-nft token-id) false) account)
)

(define-private (is-approved-or-owner (token-id uint) (account principal))
  (or
    (is-token-owner token-id account)
    (is-eq (default-to account (map-get? token-approvals token-id)) account)
    (default-to false (map-get? operator-approvals { owner: (unwrap! (nft-get-owner? stacks-nft token-id) false), operator: account }))
  )
)

;; =============================================
;; SIP-009 Trait Implementation
;; =============================================

;; Get last token ID
(define-read-only (get-last-token-id)
  (ok (var-get last-token-id))
)

;; Get token URI
(define-read-only (get-token-uri (token-id uint))
  (ok (some (var-get base-uri)))
)

;; Get token owner
(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? stacks-nft token-id))
)

;; Transfer NFT
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (not (var-get contract-paused)) ERR-PAUSED)
    (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-approved-or-owner token-id sender) ERR-NOT-AUTHORIZED)
    ;; Clear approval on transfer
    (map-delete token-approvals token-id)
    ;; Remove any listing
    (map-delete listings token-id)
    (match (nft-transfer? stacks-nft token-id sender recipient)
      success (begin
        (print { type: "nft-transfer", token-id: token-id, sender: sender, recipient: recipient })
        (ok true)
      )
      error ERR-TRANSFER-FAILED
    )
  )
)

;; =============================================
;; Minting Functions
;; =============================================

;; Public mint with payment
(define-public (mint (name (string-ascii 64)) (description (string-ascii 256)) (attributes (string-ascii 256)))
  (let (
    (new-id (+ (var-get last-token-id) u1))
  )
    (asserts! (not (var-get contract-paused)) ERR-PAUSED)
    (asserts! (var-get mint-enabled) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-id MAX-SUPPLY) ERR-MINT-LIMIT-REACHED)
    ;; Charge mint price
    (try! (stx-transfer? MINT-PRICE tx-sender CONTRACT-OWNER))
    ;; Mint the NFT
    (match (nft-mint? stacks-nft new-id tx-sender)
      success (begin
        (var-set last-token-id new-id)
        (map-set token-metadata new-id {
          name: name,
          description: description,
          attributes: attributes,
          minted-at: block-height,
          minted-by: tx-sender
        })
        (print { type: "nft-mint", token-id: new-id, minter: tx-sender, price: MINT-PRICE })
        (ok new-id)
      )
      error ERR-ALREADY-MINTED
    )
  )
)

;; Owner mint (free, no limit check)
(define-public (owner-mint (recipient principal) (name (string-ascii 64)) (description (string-ascii 256)) (attributes (string-ascii 256)))
  (let (
    (new-id (+ (var-get last-token-id) u1))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-id MAX-SUPPLY) ERR-MINT-LIMIT-REACHED)
    (match (nft-mint? stacks-nft new-id recipient)
      success (begin
        (var-set last-token-id new-id)
        (map-set token-metadata new-id {
          name: name,
          description: description,
          attributes: attributes,
          minted-at: block-height,
          minted-by: tx-sender
        })
        (print { type: "nft-owner-mint", token-id: new-id, recipient: recipient })
        (ok new-id)
      )
      error ERR-ALREADY-MINTED
    )
  )
)

;; =============================================
;; Burning Functions
;; =============================================

;; Burn NFT
(define-public (burn (token-id uint))
  (begin
    (asserts! (is-token-owner token-id tx-sender) ERR-NOT-AUTHORIZED)
    ;; Clear metadata and listings
    (map-delete token-metadata token-id)
    (map-delete listings token-id)
    (map-delete token-approvals token-id)
    (match (nft-burn? stacks-nft token-id tx-sender)
      success (begin
        (print { type: "nft-burn", token-id: token-id, burner: tx-sender })
        (ok true)
      )
      error ERR-BURN-FAILED
    )
  )
)

;; =============================================
;; Marketplace Functions
;; =============================================

;; List NFT for sale
(define-public (list-for-sale (token-id uint) (price uint))
  (begin
    (asserts! (not (var-get contract-paused)) ERR-PAUSED)
    (asserts! (is-token-owner token-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> price u0) ERR-WRONG-PRICE)
    (map-set listings token-id { price: price, seller: tx-sender })
    (print { type: "nft-listed", token-id: token-id, price: price, seller: tx-sender })
    (ok true)
  )
)

;; Remove listing
(define-public (unlist (token-id uint))
  (begin
    (asserts! (is-token-owner token-id tx-sender) ERR-NOT-AUTHORIZED)
    (map-delete listings token-id)
    (print { type: "nft-unlisted", token-id: token-id })
    (ok true)
  )
)

;; Buy listed NFT
(define-public (buy (token-id uint))
  (let (
    (listing (unwrap! (map-get? listings token-id) ERR-LISTING-NOT-FOUND))
    (price (get price listing))
    (seller (get seller listing))
    (royalty-amount (/ (* price ROYALTY-PERCENT) u100))
    (seller-amount (- price royalty-amount))
  )
    (asserts! (not (var-get contract-paused)) ERR-PAUSED)
    ;; Pay royalty to royalty address
    (if (> royalty-amount u0)
      (try! (stx-transfer? royalty-amount tx-sender (var-get royalty-address)))
      true
    )
    ;; Pay seller
    (try! (stx-transfer? seller-amount tx-sender seller))
    ;; Transfer NFT
    (try! (nft-transfer? stacks-nft token-id seller tx-sender))
    ;; Clear listing and approval
    (map-delete listings token-id)
    (map-delete token-approvals token-id)
    (print { type: "nft-sold", token-id: token-id, price: price, buyer: tx-sender, seller: seller, royalty: royalty-amount })
    (ok true)
  )
)

;; =============================================
;; Approval Functions
;; =============================================

;; Approve single token
(define-public (approve (token-id uint) (approved principal))
  (begin
    (asserts! (is-token-owner token-id tx-sender) ERR-NOT-AUTHORIZED)
    (map-set token-approvals token-id approved)
    (print { type: "nft-approval", token-id: token-id, approved: approved })
    (ok true)
  )
)

;; Set approval for all
(define-public (set-approval-for-all (operator principal) (approved bool))
  (begin
    (map-set operator-approvals { owner: tx-sender, operator: operator } approved)
    (print { type: "nft-approval-all", owner: tx-sender, operator: operator, approved: approved })
    (ok true)
  )
)

;; =============================================
;; Admin Functions
;; =============================================

(define-public (set-base-uri (new-uri (string-ascii 256)))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set base-uri new-uri)
    (ok true)
  )
)

(define-public (set-mint-enabled (enabled bool))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set mint-enabled enabled)
    (ok true)
  )
)

(define-public (set-royalty-address (new-address principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set royalty-address new-address)
    (ok true)
  )
)

(define-public (pause)
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause)
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)

;; =============================================
;; Read-Only Functions
;; =============================================

(define-read-only (get-token-metadata (token-id uint))
  (ok (map-get? token-metadata token-id))
)

(define-read-only (get-listing (token-id uint))
  (ok (map-get? listings token-id))
)

(define-read-only (get-mint-price)
  (ok MINT-PRICE)
)

(define-read-only (get-max-supply)
  (ok MAX-SUPPLY)
)

(define-read-only (get-collection-name)
  (ok COLLECTION-NAME)
)

(define-read-only (get-collection-symbol)
  (ok COLLECTION-SYMBOL)
)

(define-read-only (is-mint-enabled)
  (ok (var-get mint-enabled))
)

(define-read-only (get-royalty-info)
  (ok { address: (var-get royalty-address), percent: ROYALTY-PERCENT })
)

(define-read-only (get-total-minted)
  (ok (var-get last-token-id))
)
