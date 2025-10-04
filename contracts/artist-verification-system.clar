;; Artist Verification System Contract
;; A comprehensive system for verifying street artists and distinguishing between commissioned murals and unauthorized graffiti

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_ARTIST_NOT_FOUND (err u201))
(define-constant ERR_ARTIST_ALREADY_EXISTS (err u202))
(define-constant ERR_INVALID_PARAMETERS (err u203))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u204))
(define-constant ERR_VERIFICATION_PENDING (err u205))
(define-constant ERR_ALREADY_VERIFIED (err u206))
(define-constant ERR_MURAL_NOT_FOUND (err u207))
(define-constant ERR_INVALID_STATUS (err u208))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u209))

;; Data structures
(define-map artists
    { artist-wallet: principal }
    {
        artist-name: (string-utf8 100),
        bio: (string-utf8 500),
        verified: bool,
        verification-level: uint,
        registration-date: uint,
        portfolio-ipfs: (string-utf8 64),
        social-links: (string-utf8 300),
        reputation-score: uint,
        total-murals: uint,
        commissioned-works: uint,
        community-votes: uint,
        status: (string-utf8 20)
    }
)

(define-map mural-classifications
    { mural-id: uint }
    {
        artist: principal,
        title: (string-utf8 100),
        location: (string-utf8 200),
        classification: (string-utf8 30),
        commissioned: bool,
        commissioner: (optional principal),
        permit-number: (optional (string-utf8 50)),
        creation-date: uint,
        verification-date: uint,
        legal-status: (string-utf8 20),
        community-support: uint,
        reported-issues: uint
    }
)

(define-map verification-requests
    { request-id: uint }
    {
        artist: principal,
        requested-at: uint,
        verification-documents: (string-utf8 100),
        status: (string-utf8 20),
        reviewer: (optional principal),
        reviewed-at: (optional uint),
        review-notes: (optional (string-utf8 300))
    }
)

(define-map artist-endorsements
    { artist: principal, endorser: principal }
    {
        endorsed-at: uint,
        endorsement-type: (string-utf8 30),
        notes: (string-utf8 200)
    }
)

(define-map community-votes
    { mural-id: uint, voter: principal }
    {
        vote: (string-utf8 20),
        vote-date: uint,
        comments: (optional (string-utf8 200))
    }
)

;; Data variables
(define-data-var next-request-id uint u1)
(define-data-var next-mural-id uint u1)
(define-data-var verification-fee uint u2000000) ;; 2 STX in micro-STX
(define-data-var endorsement-reward uint u100000) ;; 0.1 STX reward
(define-data-var total-artists uint u0)
(define-data-var total-verified-artists uint u0)
(define-data-var total-murals uint u0)
(define-data-var contract-paused bool false)
(define-data-var min-reputation-for-endorsement uint u50)

;; Private functions
(define-private (is-valid-classification (classification (string-utf8 30)))
    (or 
        (is-eq classification u"mural")
        (is-eq classification u"graffiti")
        (is-eq classification u"street-art")
        (is-eq classification u"public-art")
        (is-eq classification u"commissioned")
        (is-eq classification u"unauthorized")
    )
)

(define-private (calculate-artist-reputation (artist principal))
    (let (
        (artist-data (unwrap! (map-get? artists { artist-wallet: artist }) u0))
    )
        (+ 
            (* (get commissioned-works artist-data) u20)
            (* (get community-votes artist-data) u5)
            (if (get verified artist-data) u50 u0)
            (* (get verification-level artist-data) u10)
        )
    )
)

(define-private (update-artist-stats (artist principal) (action (string-utf8 20)))
    (let (
        (current-artist (unwrap! (map-get? artists { artist-wallet: artist }) false))
    )
        (if (is-eq action u"new-mural")
            (map-set artists
                { artist-wallet: artist }
                (merge current-artist 
                    { 
                        total-murals: (+ (get total-murals current-artist) u1),
                        reputation-score: (calculate-artist-reputation artist)
                    }
                )
            )
            (if (is-eq action u"commissioned")
                (map-set artists
                    { artist-wallet: artist }
                    (merge current-artist 
                        { 
                            commissioned-works: (+ (get commissioned-works current-artist) u1),
                            reputation-score: (calculate-artist-reputation artist)
                        }
                    )
                )
                false
            )
        )
    )
)

;; Public functions
(define-public (register-artist 
    (artist-name (string-utf8 100))
    (bio (string-utf8 500))
    (portfolio-ipfs (string-utf8 64))
    (social-links (string-utf8 300))
)
    (let (
        (existing-artist (map-get? artists { artist-wallet: tx-sender }))
    )
        (asserts! (not (var-get contract-paused)) ERR_NOT_AUTHORIZED)
        (asserts! (is-none existing-artist) ERR_ARTIST_ALREADY_EXISTS)
        (asserts! (> (len artist-name) u0) ERR_INVALID_PARAMETERS)
        (asserts! (>= (stx-get-balance tx-sender) (var-get verification-fee)) ERR_INSUFFICIENT_PAYMENT)
        
        ;; Transfer registration fee
        (try! (stx-transfer? (var-get verification-fee) tx-sender CONTRACT_OWNER))
        
        ;; Register artist
        (map-set artists
            { artist-wallet: tx-sender }
            {
                artist-name: artist-name,
                bio: bio,
                verified: false,
                verification-level: u0,
                registration-date: stacks-block-height,
                portfolio-ipfs: portfolio-ipfs,
                social-links: social-links,
                reputation-score: u0,
                total-murals: u0,
                commissioned-works: u0,
                community-votes: u0,
                status: u"active"
            }
        )
        
        (var-set total-artists (+ (var-get total-artists) u1))
        (print { event: "artist-registered", artist: tx-sender, name: artist-name })
        (ok true)
    )
)

(define-public (request-verification (verification-documents (string-utf8 100)))
    (let (
        (request-id (var-get next-request-id))
        (artist-data (unwrap! (map-get? artists { artist-wallet: tx-sender }) ERR_ARTIST_NOT_FOUND))
    )
        (asserts! (not (var-get contract-paused)) ERR_NOT_AUTHORIZED)
        (asserts! (not (get verified artist-data)) ERR_ALREADY_VERIFIED)
        (asserts! (> (len verification-documents) u0) ERR_INVALID_PARAMETERS)
        
        (map-set verification-requests
            { request-id: request-id }
            {
                artist: tx-sender,
                requested-at: stacks-block-height,
                verification-documents: verification-documents,
                status: u"pending",
                reviewer: none,
                reviewed-at: none,
                review-notes: none
            }
        )
        
        (var-set next-request-id (+ request-id u1))
        (print { event: "verification-requested", artist: tx-sender, request-id: request-id })
        (ok request-id)
    )
)

(define-public (classify-mural
    (artist principal)
    (title (string-utf8 100))
    (location (string-utf8 200))
    (classification (string-utf8 30))
    (commissioned bool)
    (commissioner (optional principal))
    (permit-number (optional (string-utf8 50)))
    (creation-date uint)
)
    (let (
        (mural-id (var-get next-mural-id))
        (artist-data (unwrap! (map-get? artists { artist-wallet: artist }) ERR_ARTIST_NOT_FOUND))
    )
        (asserts! (not (var-get contract-paused)) ERR_NOT_AUTHORIZED)
        (asserts! (is-valid-classification classification) ERR_INVALID_PARAMETERS)
        (asserts! (> (len title) u0) ERR_INVALID_PARAMETERS)
        
        ;; Create mural classification record
        (map-set mural-classifications
            { mural-id: mural-id }
            {
                artist: artist,
                title: title,
                location: location,
                classification: classification,
                commissioned: commissioned,
                commissioner: commissioner,
                permit-number: permit-number,
                creation-date: creation-date,
                verification-date: stacks-block-height,
                legal-status: (if commissioned u"legal" u"unverified"),
                community-support: u0,
                reported-issues: u0
            }
        )
        
        ;; Update artist stats
        (update-artist-stats artist u"new-mural")
        (if commissioned
            (update-artist-stats artist u"commissioned")
            true
        )
        
        (var-set next-mural-id (+ mural-id u1))
        (var-set total-murals (+ (var-get total-murals) u1))
        
        (print { event: "mural-classified", mural-id: mural-id, artist: artist, commissioned: commissioned })
        (ok mural-id)
    )
)

(define-public (endorse-artist (artist principal) (endorsement-type (string-utf8 30)) (notes (string-utf8 200)))
    (let (
        (endorser-data (unwrap! (map-get? artists { artist-wallet: tx-sender }) ERR_ARTIST_NOT_FOUND))
        (artist-data (unwrap! (map-get? artists { artist-wallet: artist }) ERR_ARTIST_NOT_FOUND))
        (existing-endorsement (map-get? artist-endorsements { artist: artist, endorser: tx-sender }))
    )
        (asserts! (not (var-get contract-paused)) ERR_NOT_AUTHORIZED)
        (asserts! (not (is-eq tx-sender artist)) ERR_NOT_AUTHORIZED)
        (asserts! (is-none existing-endorsement) ERR_ALREADY_VERIFIED)
        (asserts! (>= (get reputation-score endorser-data) (var-get min-reputation-for-endorsement)) ERR_INSUFFICIENT_REPUTATION)
        
        ;; Create endorsement
        (map-set artist-endorsements
            { artist: artist, endorser: tx-sender }
            {
                endorsed-at: stacks-block-height,
                endorsement-type: endorsement-type,
                notes: notes
            }
        )
        
        ;; Update artist community votes
        (map-set artists
            { artist-wallet: artist }
            (merge artist-data 
                { 
                    community-votes: (+ (get community-votes artist-data) u1),
                    reputation-score: (calculate-artist-reputation artist)
                }
            )
        )
        
        ;; Reward endorser
        (try! (stx-transfer? (var-get endorsement-reward) CONTRACT_OWNER tx-sender))
        
        (print { event: "artist-endorsed", artist: artist, endorser: tx-sender, type: endorsement-type })
        (ok true)
    )
)

(define-public (vote-on-mural (mural-id uint) (vote (string-utf8 20)) (comments (optional (string-utf8 200))))
    (let (
        (mural (unwrap! (map-get? mural-classifications { mural-id: mural-id }) ERR_MURAL_NOT_FOUND))
        (existing-vote (map-get? community-votes { mural-id: mural-id, voter: tx-sender }))
    )
        (asserts! (not (var-get contract-paused)) ERR_NOT_AUTHORIZED)
        (asserts! (is-none existing-vote) ERR_ALREADY_VERIFIED)
        (asserts! (or (is-eq vote u"support") (is-eq vote u"oppose") (is-eq vote u"neutral")) ERR_INVALID_PARAMETERS)
        
        ;; Record vote
        (map-set community-votes
            { mural-id: mural-id, voter: tx-sender }
            {
                vote: vote,
                vote-date: stacks-block-height,
                comments: comments
            }
        )
        
        ;; Update mural community support
        (let (
            (support-change (if (is-eq vote u"support") 1 (if (is-eq vote u"oppose") -1 0)))
        )
            (map-set mural-classifications
                { mural-id: mural-id }
                (merge mural 
                    { 
                        community-support: (if (> support-change 0) 
                            (+ (get community-support mural) u1)
                            (if (< support-change 0)
                                (if (> (get community-support mural) u0) (- (get community-support mural) u1) u0)
                                (get community-support mural)
                            )
                        )
                    }
                )
            )
        )
        
        (print { event: "mural-vote-cast", mural-id: mural-id, voter: tx-sender, vote: vote })
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-artist (artist-wallet principal))
    (map-get? artists { artist-wallet: artist-wallet })
)

(define-read-only (get-mural-classification (mural-id uint))
    (map-get? mural-classifications { mural-id: mural-id })
)

(define-read-only (get-verification-request (request-id uint))
    (map-get? verification-requests { request-id: request-id })
)

(define-read-only (get-artist-endorsement (artist principal) (endorser principal))
    (map-get? artist-endorsements { artist: artist, endorser: endorser })
)

(define-read-only (get-community-vote (mural-id uint) (voter principal))
    (map-get? community-votes { mural-id: mural-id, voter: voter })
)

(define-read-only (get-contract-stats)
    {
        total-artists: (var-get total-artists),
        total-verified-artists: (var-get total-verified-artists),
        total-murals: (var-get total-murals),
        next-request-id: (var-get next-request-id),
        next-mural-id: (var-get next-mural-id),
        verification-fee: (var-get verification-fee),
        endorsement-reward: (var-get endorsement-reward),
        contract-paused: (var-get contract-paused)
    }
)

;; Admin functions
(define-public (approve-verification (request-id uint) (verification-level uint) (review-notes (string-utf8 300)))
    (let (
        (request (unwrap! (map-get? verification-requests { request-id: request-id }) ERR_VERIFICATION_PENDING))
        (artist-data (unwrap! (map-get? artists { artist-wallet: (get artist request) }) ERR_ARTIST_NOT_FOUND))
    )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq (get status request) u"pending") ERR_VERIFICATION_PENDING)
        
        ;; Update verification request
        (map-set verification-requests
            { request-id: request-id }
            (merge request 
                {
                    status: u"approved",
                    reviewer: (some tx-sender),
                    reviewed-at: (some stacks-block-height),
                    review-notes: (some review-notes)
                }
            )
        )
        
        ;; Update artist verification status
        (map-set artists
            { artist-wallet: (get artist request) }
            (merge artist-data 
                {
                    verified: true,
                    verification-level: verification-level,
                    reputation-score: (calculate-artist-reputation (get artist request))
                }
            )
        )
        
        (var-set total-verified-artists (+ (var-get total-verified-artists) u1))
        (print { event: "verification-approved", request-id: request-id, artist: (get artist request) })
        (ok true)
    )
)

(define-public (set-verification-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set verification-fee new-fee)
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

;; title: artist-verification-system
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

