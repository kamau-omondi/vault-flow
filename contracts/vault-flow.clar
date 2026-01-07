;; Title: VaultFlow Pro - Advanced Bitcoin Yield Aggregation Protocol
;; Summary: A sophisticated DeFi protocol that enables Bitcoin holders to earn 
;;          optimized yields through intelligent staking mechanisms while maintaining
;;          full custody and liquidity through tokenized representations.
;; Description: 
;; VaultFlow Pro revolutionizes Bitcoin yield generation by creating a decentralized
;; infrastructure where users can stake their Bitcoin and receive stBTC tokens 
;; representing their position. The protocol employs advanced yield optimization 
;; algorithms, risk assessment scoring, and optional insurance coverage to maximize
;; returns while minimizing exposure. Features include:
;;
;; - Dynamic yield distribution with compound interest calculations
;; - Integrated risk scoring system for portfolio optimization  
;; - Optional insurance fund for additional security layers
;; - Real-time yield tracking and performance analytics
;; - SIP-010 compliant tokenized staking positions
;; - Flexible staking/unstaking with instant liquidity
;;
;; The protocol is designed for institutional and retail investors seeking sustainable
;; Bitcoin yield generation without compromising on security or accessibility.

;; PROTOCOL CONSTANTS
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_OWNER_ONLY (err u100))
(define-constant ERR_ALREADY_INITIALIZED (err u101))
(define-constant ERR_NOT_INITIALIZED (err u102))
(define-constant ERR_POOL_ACTIVE (err u103))
(define-constant ERR_POOL_INACTIVE (err u104))
(define-constant ERR_INVALID_AMOUNT (err u105))
(define-constant ERR_INSUFFICIENT_BALANCE (err u106))
(define-constant ERR_NO_YIELD_AVAILABLE (err u107))
(define-constant ERR_MINIMUM_STAKE (err u108))
(define-constant ERR_UNAUTHORIZED (err u109))
(define-constant ERR_INVALID_YIELD_RATE (err u110))
(define-constant ERR_INVALID_RECIPIENT (err u111))
(define-constant ERR_INVALID_METADATA (err u112))
(define-constant ERR_INVALID_TIME (err u113))
(define-constant ERR_ASSET_RESTRICTION_VIOLATED (err u114))
(define-constant MINIMUM_STAKE_AMOUNT u1000000) ;; 0.01 BTC minimum entry threshold
(define-constant MAX_YIELD_RATE u5000) ;; Maximum 50% APY for security
(define-constant MIN_YIELD_RATE u100) ;; Minimum 1% APY
(define-constant SECONDS_PER_DAY u86400) ;; 24 hours in seconds

;; PROTOCOL STATE VARIABLES
(define-data-var total-staked uint u0)
(define-data-var total-yield-generated uint u0)
(define-data-var protocol-active bool false)
(define-data-var insurance-module-active bool false)
(define-data-var base-yield-rate uint u0)
(define-data-var last-yield-distribution-time uint u0)
(define-data-var insurance-reserve-balance uint u0)
(define-data-var vault-token-name (string-ascii 32) "VaultFlow Staked BTC")
(define-data-var vault-token-symbol (string-ascii 10) "vfBTC")
(define-data-var vault-token-metadata (optional (string-utf8 256)) none)

;; PROTOCOL DATA STRUCTURES
(define-map participant-balances
  principal
  uint
)
(define-map participant-accumulated-rewards
  principal
  uint
)
(define-map yield-distribution-ledger
  uint
  {
    distribution-timestamp: uint,
    total-amount-distributed: uint,
    effective-apy: uint,
  }
)
(define-map participant-risk-profiles
  principal
  uint
)
(define-map insurance-protection-coverage
  principal
  uint
)
(define-map token-transfer-allowances
  {
    owner: principal,
    spender: principal,
  }
  uint
)

;; SIP-010 STANDARD COMPLIANCE
(define-read-only (get-name)
  (ok (var-get vault-token-name))
)

(define-read-only (get-symbol)
  (ok (var-get vault-token-symbol))
)

(define-read-only (get-decimals)
  (ok u8)
)

(define-read-only (get-balance (account principal))
  (ok (default-to u0 (map-get? participant-balances account)))
)

(define-read-only (get-total-supply)
  (ok (var-get total-staked))
)

(define-read-only (get-token-uri)
  (ok (var-get vault-token-metadata))
)

;; INTERNAL PROTOCOL FUNCTIONS
(define-private (compute-yield-amount
    (principal-amount uint)
    (time-seconds uint)
  )
  (let (
      (current-rate (var-get base-yield-rate))
      (days-elapsed (/ time-seconds SECONDS_PER_DAY))
      (base-yield-calculation (* principal-amount current-rate))
      (annual-divisor (* u365 u10000)) ;; Convert APY to daily rate
    )
    ;; Calculate yield: (principal * rate * days) / (365 * 10000)
    (/ (* (* base-yield-calculation days-elapsed) u1) annual-divisor)
  )
)

(define-private (update-participant-risk-profile
    (participant principal)
    (stake-amount uint)
  )
  (let (
      (existing-risk-score (default-to u0 (map-get? participant-risk-profiles participant)))
      (stake-impact-factor (/ stake-amount u100000000)) ;; Risk factor based on position size
      (updated-risk-score (+ existing-risk-score stake-impact-factor))
    )
    (map-set participant-risk-profiles participant updated-risk-score)
    updated-risk-score
  )
)

(define-private (validate-yield-distribution-eligibility)
  (let (
      (current-time stacks-block-time)
      (previous-distribution-time (var-get last-yield-distribution-time))
      (time-since-last (- current-time previous-distribution-time))
    )
    ;; Require at least 1 day between distributions
    (if (>= time-since-last SECONDS_PER_DAY)
      (ok true)
      ERR_NO_YIELD_AVAILABLE
    )
  )
)

(define-private (execute-internal-token-transfer
    (transfer-amount uint)
    (from-account principal)
    (to-account principal)
  )
  (let ((sender-current-balance (default-to u0 (map-get? participant-balances from-account))))
    (asserts! (>= sender-current-balance transfer-amount)
      ERR_INSUFFICIENT_BALANCE
    )

    (map-set participant-balances from-account
      (- sender-current-balance transfer-amount)
    )
    (map-set participant-balances to-account
      (+ (default-to u0 (map-get? participant-balances to-account))
        transfer-amount
      ))
    (ok true)
  )
)

;; PROTOCOL MANAGEMENT FUNCTIONS
(define-public (initialize-vaultflow-protocol (initial-yield-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (not (var-get protocol-active)) ERR_ALREADY_INITIALIZED)
    (asserts!
      (and
        (>= initial-yield-rate MIN_YIELD_RATE)
        (<= initial-yield-rate MAX_YIELD_RATE)
      )
      ERR_INVALID_YIELD_RATE
    )
    (var-set protocol-active true)
    (var-set base-yield-rate initial-yield-rate)
    (var-set last-yield-distribution-time stacks-block-time)
    (ok true)
  )
)

;; CORE STAKING FUNCTIONS
(define-public (deposit-and-stake (deposit-amount uint))
  (begin
    (asserts! (var-get protocol-active) ERR_POOL_INACTIVE)
    (asserts! (>= deposit-amount MINIMUM_STAKE_AMOUNT) ERR_MINIMUM_STAKE)

    ;; Update participant position
    (let (
        (existing-participant-balance (default-to u0 (map-get? participant-balances tx-sender)))
        (updated-participant-balance (+ existing-participant-balance deposit-amount))
      )
      (map-set participant-balances tx-sender updated-participant-balance)
      (var-set total-staked (+ (var-get total-staked) deposit-amount))

      ;; Update risk assessment
      (update-participant-risk-profile tx-sender deposit-amount)

      ;; Activate insurance coverage if enabled
      (if (var-get insurance-module-active)
        (map-set insurance-protection-coverage tx-sender deposit-amount)
        true
      )

      ;; Enhanced logging with Clarity 4 to-ascii?
      (print {
        event: "stake",
        user: tx-sender,
        amount: deposit-amount,
        new-balance: updated-participant-balance,
        timestamp: stacks-block-time
      })

      (ok true)
    )
  )
)

(define-public (withdraw-and-unstake (withdrawal-amount uint))
  (let ((participant-current-balance (default-to u0 (map-get? participant-balances tx-sender))))
    (asserts! (var-get protocol-active) ERR_POOL_INACTIVE)
    (asserts! (>= participant-current-balance withdrawal-amount)
      ERR_INSUFFICIENT_BALANCE
    )

    ;; Process any pending yield rewards before withdrawal
    (try! (harvest-accumulated-yield))

    ;; Execute withdrawal
    (map-set participant-balances tx-sender
      (- participant-current-balance withdrawal-amount)
    )
    (var-set total-staked (- (var-get total-staked) withdrawal-amount))

    ;; Adjust insurance coverage if applicable
    (if (var-get insurance-module-active)
      (map-set insurance-protection-coverage tx-sender
        (- participant-current-balance withdrawal-amount)
      )
      true
    )

    ;; Enhanced logging with Clarity 4
    (print {
      event: "unstake",
      user: tx-sender,
      amount: withdrawal-amount,
      new-balance: (- participant-current-balance withdrawal-amount),
      timestamp: stacks-block-time
    })

    (ok true)
  )
)

;; YIELD DISTRIBUTION SYSTEM
(define-public (execute-protocol-yield-distribution)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (var-get protocol-active) ERR_POOL_INACTIVE)
    (try! (validate-yield-distribution-eligibility))

    (let (
        (current-time stacks-block-time)
        (elapsed-seconds (- current-time (var-get last-yield-distribution-time)))
        (total-yield-to-distribute (compute-yield-amount (var-get total-staked) elapsed-seconds))
      )
      ;; Update protocol yield metrics
      (var-set total-yield-generated
        (+ (var-get total-yield-generated) total-yield-to-distribute)
      )
      (var-set last-yield-distribution-time current-time)

      ;; Record distribution event
      (map-set yield-distribution-ledger current-time {
        distribution-timestamp: current-time,
        total-amount-distributed: total-yield-to-distribute,
        effective-apy: (var-get base-yield-rate),
      })

      (ok total-yield-to-distribute)
    )
  )
)

(define-public (harvest-accumulated-yield)
  (begin
    (asserts! (var-get protocol-active) ERR_POOL_INACTIVE)

    (let (
        (participant-stake-balance (default-to u0 (map-get? participant-balances tx-sender)))
        (existing-rewards (default-to u0 (map-get? participant-accumulated-rewards tx-sender)))
        (seconds-since-last-distribution (- stacks-block-time (var-get last-yield-distribution-time)))
        (newly-generated-rewards (compute-yield-amount participant-stake-balance
          seconds-since-last-distribution
        ))
        (total-harvestable-rewards (+ existing-rewards newly-generated-rewards))
      )
      (asserts! (> total-harvestable-rewards u0) ERR_NO_YIELD_AVAILABLE)

      ;; Process reward harvest
      (map-set participant-accumulated-rewards tx-sender u0)
      (map-set participant-balances tx-sender
        (+ participant-stake-balance total-harvestable-rewards)
      )

      ;; Enhanced logging
      (print {
        event: "yield-harvest",
        user: tx-sender,
        rewards: total-harvestable-rewards,
        new-balance: (+ participant-stake-balance total-harvestable-rewards),
        timestamp: stacks-block-time
      })

      (ok total-harvestable-rewards)
    )
  )
)

;; TOKEN TRANSFER FUNCTIONS
(define-public (transfer
    (amount uint)
    (sender principal)
    (recipient principal)
    (memo (optional (buff 34)))
  )
  (begin
    (asserts! (is-eq tx-sender sender) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (not (is-eq sender recipient)) ERR_INVALID_RECIPIENT)
    (asserts! (is-standard recipient) ERR_INVALID_RECIPIENT)
    (try! (execute-internal-token-transfer amount sender recipient))
    (match memo
      memo-data (print memo-data)
      0x
    )
    (ok true)
  )
)

;; SECURE TRANSFER WITH ASSET RESTRICTIONS (Clarity 4)
;; Note: restrict-assets? requires non-response body, so we use a helper
(define-private (internal-transfer-helper
    (amount uint)
    (sender principal)
    (recipient principal)
  )
  (let ((sender-balance (default-to u0 (map-get? participant-balances sender))))
    (if (>= sender-balance amount)
      (begin
        (map-set participant-balances sender (- sender-balance amount))
        (map-set participant-balances recipient
          (+ (default-to u0 (map-get? participant-balances recipient)) amount))
        true
      )
      false
    )
  )
)

(define-public (secure-transfer
    (amount uint)
    (recipient principal)
  )
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (not (is-eq tx-sender recipient)) ERR_INVALID_RECIPIENT)
    (asserts! (is-standard recipient) ERR_INVALID_RECIPIENT)
    
    ;; Use restrict-assets? to ensure no unauthorized asset movements
    ;; The body must not return a response type
    (match (restrict-assets? tx-sender ()
      (internal-transfer-helper amount tx-sender recipient)
    )
      success (ok success)
      error-index ERR_ASSET_RESTRICTION_VIOLATED
    )
  )
)

(define-public (update-token-metadata (new-metadata (optional (string-utf8 256))))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    ;; Validate and safely set metadata
    (match new-metadata
      metadata-value
      (begin
        (asserts! (> (len metadata-value) u0) ERR_INVALID_METADATA)
        (asserts! (<= (len metadata-value) u256) ERR_INVALID_METADATA)
        ;; Create validated optional with the checked value
        (let ((validated-metadata (some metadata-value)))
          (var-set vault-token-metadata validated-metadata)
          (ok true)
        )
      )
      ;; If none, safely clear metadata
      (begin
        (var-set vault-token-metadata none)
        (ok true)
      )
    )
  )
)

;; PROTOCOL ANALYTICS & QUERIES
(define-read-only (get-participant-stake-info (participant principal))
  (ok (default-to u0 (map-get? participant-balances participant)))
)

(define-read-only (get-participant-reward-balance (participant principal))
  (ok (default-to u0 (map-get? participant-accumulated-rewards participant)))
)

(define-read-only (get-comprehensive-protocol-metrics)
  (ok {
    total-value-locked: (var-get total-staked),
    cumulative-yield-distributed: (var-get total-yield-generated),
    current-base-apy: (var-get base-yield-rate),
    protocol-status: (var-get protocol-active),
    insurance-module-status: (var-get insurance-module-active),
    insurance-reserve-tvl: (var-get insurance-reserve-balance),
    last-distribution-time: (var-get last-yield-distribution-time),
    current-time: stacks-block-time,
  })
)

(define-read-only (get-participant-risk-assessment (participant principal))
  (ok (default-to u0 (map-get? participant-risk-profiles participant)))
)

;; NEW CLARITY 4 ENHANCED FUNCTIONS
(define-read-only (get-participant-detailed-info (participant principal))
  (ok {
    balance: (default-to u0 (map-get? participant-balances participant)),
    rewards: (default-to u0 (map-get? participant-accumulated-rewards participant)),
    risk-score: (default-to u0 (map-get? participant-risk-profiles participant)),
    insurance-coverage: (default-to u0 (map-get? insurance-protection-coverage participant)),
  })
)

(define-read-only (get-time-since-last-distribution)
  (ok (- stacks-block-time (var-get last-yield-distribution-time)))
)

(define-read-only (can-distribute-yield)
  (let (
      (time-since-last (- stacks-block-time (var-get last-yield-distribution-time)))
    )
    (ok (>= time-since-last SECONDS_PER_DAY))
  )
)

(define-read-only (estimate-pending-yield (participant principal))
  (let (
      (stake-balance (default-to u0 (map-get? participant-balances participant)))
      (time-elapsed (- stacks-block-time (var-get last-yield-distribution-time)))
    )
    (ok (compute-yield-amount stake-balance time-elapsed))
  )
)

;; PROTOCOL MANAGEMENT FUNCTIONS (Enhanced)
(define-public (update-yield-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (and (>= new-rate MIN_YIELD_RATE) (<= new-rate MAX_YIELD_RATE)) 
      ERR_INVALID_YIELD_RATE)
    (var-set base-yield-rate new-rate)
    (print {
      event: "yield-rate-updated",
      old-rate: (var-get base-yield-rate),
      new-rate: new-rate,
      timestamp: stacks-block-time
    })
    (ok true)
  )
)

(define-public (toggle-insurance-module (enable bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (var-set insurance-module-active enable)
    (print {
      event: "insurance-module-toggled",
      enabled: enable,
      timestamp: stacks-block-time
    })
    (ok true)
  )
)

;; PROTOCOL INITIALIZATION
(begin
  (var-set protocol-active false)
  (var-set insurance-module-active false)
  (var-set base-yield-rate u750) ;; 7.5% optimized base APY
  (var-set last-yield-distribution-time stacks-block-time)
)
