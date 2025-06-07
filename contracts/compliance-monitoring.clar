;; Compliance Monitoring Contract
;; Monitors defense compliance and audit trails

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_AUDIT_NOT_FOUND (err u401))
(define-constant ERR_INVALID_SCORE (err u402))

;; Compliance levels
(define-constant COMPLIANCE_CRITICAL u1)
(define-constant COMPLIANCE_HIGH u2)
(define-constant COMPLIANCE_MEDIUM u3)
(define-constant COMPLIANCE_LOW u4)

;; Data structures
(define-map compliance-records
  { entity: principal, record-id: uint }
  {
    audit-type: (string-ascii 50),
    compliance-score: uint,
    findings: (string-ascii 500),
    auditor: principal,
    audit-date: uint,
    next-audit-due: uint,
    status: uint
  }
)

(define-map compliance-violations
  { entity: principal, violation-id: uint }
  {
    violation-type: (string-ascii 100),
    severity: uint,
    description: (string-ascii 300),
    reported-date: uint,
    resolved: bool,
    resolution-date: (optional uint)
  }
)

(define-map entity-compliance-status
  { entity: principal }
  {
    overall-score: uint,
    last-audit-date: uint,
    compliance-level: uint,
    active-violations: uint
  }
)

(define-map entity-record-counters { entity: principal } { record-count: uint, violation-count: uint })

;; Public functions
(define-public (record-audit
  (entity principal)
  (audit-type (string-ascii 50))
  (compliance-score uint)
  (findings (string-ascii 500))
  (next-audit-interval uint)
)
  (let (
    (counters (default-to { record-count: u0, violation-count: u0 } (map-get? entity-record-counters { entity: entity })))
    (record-id (+ (get record-count counters) u1))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= compliance-score u100) ERR_INVALID_SCORE)

    (map-set compliance-records
      { entity: entity, record-id: record-id }
      {
        audit-type: audit-type,
        compliance-score: compliance-score,
        findings: findings,
        auditor: tx-sender,
        audit-date: block-height,
        next-audit-due: (+ block-height next-audit-interval),
        status: u1
      }
    )

    ;; Update entity compliance status
    (map-set entity-compliance-status
      { entity: entity }
      {
        overall-score: compliance-score,
        last-audit-date: block-height,
        compliance-level: (if (>= compliance-score u90) COMPLIANCE_LOW
          (if (>= compliance-score u75) COMPLIANCE_MEDIUM
            (if (>= compliance-score u60) COMPLIANCE_HIGH COMPLIANCE_CRITICAL)
          )
        ),
        active-violations: (default-to u0 (get active-violations (map-get? entity-compliance-status { entity: entity })))
      }
    )

    (map-set entity-record-counters
      { entity: entity }
      { record-count: record-id, violation-count: (get violation-count counters) }
    )

    (ok record-id)
  )
)

(define-public (report-violation
  (entity principal)
  (violation-type (string-ascii 100))
  (severity uint)
  (description (string-ascii 300))
)
  (let (
    (counters (default-to { record-count: u0, violation-count: u0 } (map-get? entity-record-counters { entity: entity })))
    (violation-id (+ (get violation-count counters) u1))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)

    (map-set compliance-violations
      { entity: entity, violation-id: violation-id }
      {
        violation-type: violation-type,
        severity: severity,
        description: description,
        reported-date: block-height,
        resolved: false,
        resolution-date: none
      }
    )

    ;; Update active violations count
    (let ((current-status (default-to
      { overall-score: u0, last-audit-date: u0, compliance-level: COMPLIANCE_CRITICAL, active-violations: u0 }
      (map-get? entity-compliance-status { entity: entity })
    )))
      (map-set entity-compliance-status
        { entity: entity }
        (merge current-status { active-violations: (+ (get active-violations current-status) u1) })
      )
    )

    (map-set entity-record-counters
      { entity: entity }
      { record-count: (get record-count counters), violation-count: violation-id }
    )

    (ok violation-id)
  )
)

(define-public (resolve-violation (entity principal) (violation-id uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? compliance-violations { entity: entity, violation-id: violation-id })) ERR_AUDIT_NOT_FOUND)

    (map-set compliance-violations
      { entity: entity, violation-id: violation-id }
      (merge (unwrap-panic (map-get? compliance-violations { entity: entity, violation-id: violation-id }))
        { resolved: true, resolution-date: (some block-height) }
      )
    )

    ;; Decrease active violations count
    (let ((current-status (unwrap-panic (map-get? entity-compliance-status { entity: entity }))))
      (map-set entity-compliance-status
        { entity: entity }
        (merge current-status { active-violations: (- (get active-violations current-status) u1) })
      )
    )

    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-compliance-status (entity principal))
  (map-get? entity-compliance-status { entity: entity })
)

(define-read-only (get-audit-record (entity principal) (record-id uint))
  (map-get? compliance-records { entity: entity, record-id: record-id })
)

(define-read-only (get-violation (entity principal) (violation-id uint))
  (map-get? compliance-violations { entity: entity, violation-id: violation-id })
)

(define-read-only (is-compliant (entity principal) (minimum-score uint))
  (match (map-get? entity-compliance-status { entity: entity })
    status (and
      (>= (get overall-score status) minimum-score)
      (is-eq (get active-violations status) u0)
    )
    false
  )
)
