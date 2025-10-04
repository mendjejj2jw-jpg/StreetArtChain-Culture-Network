;; Street Art Documentation Registry Contract
;; A comprehensive system for documenting street art and murals with location, artist attribution, and cultural significance records

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_ARTWORK_NOT_FOUND (err u101))
(define-constant ERR_ARTWORK_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_PARAMETERS (err u103))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u104))
(define-constant ERR_ARTWORK_ALREADY_VERIFIED (err u105))
(define-constant ERR_INVALID_STATUS (err u106))

;; Data structures
(define-map artworks
    { artwork-id: uint }
    {
        creator: principal,
        title: (string-utf8 100),
        description: (string-utf8 500),
        location-lat: int,
        location-lng: int,
        address: (string-utf8 200),
        artist-name: (optional (string-utf8 100)),
        artist-wallet: (optional principal),
        creation-date: uint,
        documentation-date: uint,
        ipfs-hash: (string-utf8 64),
        cultural-significance: (string-utf8 300),
        artwork-type: (string-utf8 50),
        verified: bool,
        verification-count: uint,
        status: (string-utf8 20)
    }
)

(define-map artwork-verifications
    { artwork-id: uint, verifier: principal }
    {
        verified-at: uint,
        verification-note: (string-utf8 200)
    }
)

(define-map user-contributions
    { user: principal }
    {
        artworks-documented: uint,
        artworks-verified: uint,
        reputation-score: uint,
        total-rewards: uint
    }
)

(define-map location-artworks
    { lat-sector: int, lng-sector: int }
    { artwork-ids: (list 50 uint) }
)

;; Data variables
(define-data-var next-artwork-id uint u1)
(define-data-var documentation-fee uint u1000000) ;; 1 STX in micro-STX
(define-data-var verification-reward uint u500000) ;; 0.5 STX reward
(define-data-var contract-paused bool false)
(define-data-var total-artworks uint u0)
(define-data-var total-verified-artworks uint u0)

;; Private functions
(define-private (is-valid-coordinates (lat int) (lng int))
    (and 
        (>= lat -90000000)
        (<= lat 90000000)
        (>= lng -180000000)
        (<= lng 180000000)
    )
)

(define-private (calculate-sector (coordinate int))
    (/ coordinate 1000000) ;; Group coordinates into ~1km sectors
)

(define-private (update-user-stats (user principal) (action (string-utf8 20)))
    (let (
        (current-stats (default-to 
            { artworks-documented: u0, artworks-verified: u0, reputation-score: u0, total-rewards: u0 }
            (map-get? user-contributions { user: user })
        ))
    )
        (if (is-eq action u"documented")
            (map-set user-contributions 
                { user: user }
                (merge current-stats 
                    { 
                        artworks-documented: (+ (get artworks-documented current-stats) u1),
                        reputation-score: (+ (get reputation-score current-stats) u10)
                    }
                )
            )
            (if (is-eq action u"verified")
                (map-set user-contributions 
                    { user: user }
                    (merge current-stats 
                        { 
                            artworks-verified: (+ (get artworks-verified current-stats) u1),
                            reputation-score: (+ (get reputation-score current-stats) u5)
                        }
                    )
                )
                false
            )
        )
    )
)

;; Public functions
(define-public (document-artwork 
    (title (string-utf8 100))
    (description (string-utf8 500))
    (location-lat int)
    (location-lng int)
    (address (string-utf8 200))
    (artist-name (optional (string-utf8 100)))
    (artist-wallet (optional principal))
    (creation-date uint)
    (ipfs-hash (string-utf8 64))
    (cultural-significance (string-utf8 300))
    (artwork-type (string-utf8 50))
)
    (let (
        (artwork-id (var-get next-artwork-id))
        (lat-sector (calculate-sector location-lat))
        (lng-sector (calculate-sector location-lng))
        (current-location-artworks (default-to 
            { artwork-ids: (list) }
            (map-get? location-artworks { lat-sector: lat-sector, lng-sector: lng-sector })
        ))
    )
        (asserts! (not (var-get contract-paused)) ERR_NOT_AUTHORIZED)
        (asserts! (is-valid-coordinates location-lat location-lng) ERR_INVALID_PARAMETERS)
        (asserts! (> (len title) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (len ipfs-hash) u0) ERR_INVALID_PARAMETERS)
        (asserts! (>= (stx-get-balance tx-sender) (var-get documentation-fee)) ERR_INSUFFICIENT_PAYMENT)
        
        ;; Transfer documentation fee
        (try! (stx-transfer? (var-get documentation-fee) tx-sender CONTRACT_OWNER))
        
        ;; Create artwork record
        (map-set artworks
            { artwork-id: artwork-id }
            {
                creator: tx-sender,
                title: title,
                description: description,
                location-lat: location-lat,
                location-lng: location-lng,
                address: address,
                artist-name: artist-name,
                artist-wallet: artist-wallet,
                creation-date: creation-date,
                documentation-date: stacks-block-height,
                ipfs-hash: ipfs-hash,
                cultural-significance: cultural-significance,
                artwork-type: artwork-type,
                verified: false,
                verification-count: u0,
                status: u"active"
            }
        )
        
        ;; Update location mapping
        (map-set location-artworks
            { lat-sector: lat-sector, lng-sector: lng-sector }
            { artwork-ids: (unwrap! (as-max-len? (append (get artwork-ids current-location-artworks) artwork-id) u50) ERR_INVALID_PARAMETERS) }
        )
        
        ;; Update counters and user stats
        (var-set next-artwork-id (+ artwork-id u1))
        (var-set total-artworks (+ (var-get total-artworks) u1))
        (update-user-stats tx-sender u"documented")
        
        (print { event: "artwork-documented", artwork-id: artwork-id, creator: tx-sender })
        (ok artwork-id)
    )
)

(define-public (verify-artwork (artwork-id uint) (verification-note (string-utf8 200)))
    (let (
        (artwork (unwrap! (map-get? artworks { artwork-id: artwork-id }) ERR_ARTWORK_NOT_FOUND))
        (existing-verification (map-get? artwork-verifications { artwork-id: artwork-id, verifier: tx-sender }))
    )
        (asserts! (not (var-get contract-paused)) ERR_NOT_AUTHORIZED)
        (asserts! (is-none existing-verification) ERR_ARTWORK_ALREADY_VERIFIED)
        (asserts! (not (is-eq tx-sender (get creator artwork))) ERR_NOT_AUTHORIZED)
        
        ;; Add verification
        (map-set artwork-verifications
            { artwork-id: artwork-id, verifier: tx-sender }
            {
                verified-at: stacks-block-height,
                verification-note: verification-note
            }
        )
        
        ;; Update artwork verification count
        (let (
            (new-verification-count (+ (get verification-count artwork) u1))
            (is-now-verified (>= new-verification-count u3))
        )
            (map-set artworks
                { artwork-id: artwork-id }
                (merge artwork 
                    {
                        verification-count: new-verification-count,
                        verified: (or (get verified artwork) is-now-verified)
                    }
                )
            )
            
            ;; Update total verified artworks if newly verified
            (if (and is-now-verified (not (get verified artwork)))
                (var-set total-verified-artworks (+ (var-get total-verified-artworks) u1))
                true
            )
        )
        
        ;; Update user stats and reward verifier
        (update-user-stats tx-sender u"verified")
        (try! (stx-transfer? (var-get verification-reward) CONTRACT_OWNER tx-sender))
        
        (print { event: "artwork-verified", artwork-id: artwork-id, verifier: tx-sender })
        (ok true)
    )
)

(define-public (update-artwork-status (artwork-id uint) (new-status (string-utf8 20)))
    (let (
        (artwork (unwrap! (map-get? artworks { artwork-id: artwork-id }) ERR_ARTWORK_NOT_FOUND))
    )
        (asserts! (or (is-eq tx-sender (get creator artwork)) (is-eq tx-sender CONTRACT_OWNER)) ERR_NOT_AUTHORIZED)
        (asserts! (or (is-eq new-status u"active") (is-eq new-status u"damaged") (is-eq new-status u"removed")) ERR_INVALID_STATUS)
        
        (map-set artworks
            { artwork-id: artwork-id }
            (merge artwork { status: new-status })
        )
        
        (print { event: "artwork-status-updated", artwork-id: artwork-id, new-status: new-status })
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-artwork (artwork-id uint))
    (map-get? artworks { artwork-id: artwork-id })
)

(define-read-only (get-artwork-verification (artwork-id uint) (verifier principal))
    (map-get? artwork-verifications { artwork-id: artwork-id, verifier: verifier })
)

(define-read-only (get-user-contributions (user principal))
    (map-get? user-contributions { user: user })
)

(define-read-only (get-location-artworks (lat-sector int) (lng-sector int))
    (map-get? location-artworks { lat-sector: lat-sector, lng-sector: lng-sector })
)

(define-read-only (get-contract-stats)
    {
        total-artworks: (var-get total-artworks),
        total-verified-artworks: (var-get total-verified-artworks),
        next-artwork-id: (var-get next-artwork-id),
        documentation-fee: (var-get documentation-fee),
        verification-reward: (var-get verification-reward),
        contract-paused: (var-get contract-paused)
    }
)

;; Admin functions
(define-public (set-documentation-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set documentation-fee new-fee)
        (ok true)
    )
)

(define-public (set-verification-reward (new-reward uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set verification-reward new-reward)
        (ok true)
    )
)

(define-public (toggle-contract-pause)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set contract-paused (not (var-get contract-paused)))
        (ok (var-get contract-paused))
    )
)

;; title: street-art-documentation-registry
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

