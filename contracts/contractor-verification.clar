;; Contractor Verification Contract
;; Manages verification and registration of defense contractors

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_CONTRACTOR_EXISTS (err u101))
(define-constant ERR_CONTRACTOR_NOT_FOUND (err u102))
(define-constant ERR_INVALID_STATUS (err u103))

;; Contractor status constants
(define-constant STATUS_PENDING u0)
(define-constant STATUS_VERIFIED u1)
(define-constant STATUS_SUSPENDED u2)
(define-constant STATUS_REVOKED u3)

;; Data structures
(define-map contractors
  { contractor-id: principal }
  {
    name: (string-ascii 100),
    registration-date: uint,
    status: uint,
    cage-code: (string-ascii 20),
    verification-level: uint
  }
)

(define-map contractor-capabilities
  { contractor-id: principal }
  { capabilities: (list 10 (string-ascii 50)) }
)

(define-data-var next-contractor-id uint u1)

;; Public functions
(define-public (register-contractor (name (string-ascii 100)) (cage-code (string-ascii 20)))
  (let ((contractor-principal tx-sender))
    (asserts! (is-none (map-get? contractors { contractor-id: contractor-principal })) ERR_CONTRACTOR_EXISTS)
    (map-set contractors
      { contractor-id: contractor-principal }
      {
        name: name,
        registration-date: block-height,
        status: STATUS_PENDING,
        cage-code: cage-code,
        verification-level: u0
      }
    )
    (ok contractor-principal)
  )
)

(define-public (verify-contractor (contractor-id principal) (verification-level uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? contractors { contractor-id: contractor-id })) ERR_CONTRACTOR_NOT_FOUND)
    (map-set contractors
      { contractor-id: contractor-id }
      (merge (unwrap-panic (map-get? contractors { contractor-id: contractor-id }))
        { status: STATUS_VERIFIED, verification-level: verification-level }
      )
    )
    (ok true)
  )
)

(define-public (update-contractor-status (contractor-id principal) (new-status uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? contractors { contractor-id: contractor-id })) ERR_CONTRACTOR_NOT_FOUND)
    (asserts! (<= new-status STATUS_REVOKED) ERR_INVALID_STATUS)
    (map-set contractors
      { contractor-id: contractor-id }
      (merge (unwrap-panic (map-get? contractors { contractor-id: contractor-id }))
        { status: new-status }
      )
    )
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-contractor (contractor-id principal))
  (map-get? contractors { contractor-id: contractor-id })
)

(define-read-only (is-contractor-verified (contractor-id principal))
  (match (map-get? contractors { contractor-id: contractor-id })
    contractor (is-eq (get status contractor) STATUS_VERIFIED)
    false
  )
)

(define-read-only (get-contractor-verification-level (contractor-id principal))
  (match (map-get? contractors { contractor-id: contractor-id })
    contractor (some (get verification-level contractor))
    none
  )
)
