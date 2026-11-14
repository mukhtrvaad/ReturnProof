// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title RentalEvidenceRegistry
 * @notice Educational prototype for recording jointly acknowledged
 *         equipment handover and return evidence.
 *
 * IMPORTANT:
 * - Store only hashes and non-personal references on-chain.
 * - Store photographs and personal information off-chain.
 * - A hash proves file integrity, not that the photograph is truthful.
 */
contract RentalEvidenceRegistry {
    enum RentalStatus {
        Created,
        HandoverConfirmed,
        Returned,
        Disputed
    }

    struct Rental {
        address provider;
        address renter;
        bytes32 assetReferenceHash;
        bytes32 handoverEvidenceHash;
        bytes32 returnEvidenceHash;
        bool providerHandoverConfirmed;
        bool renterHandoverConfirmed;
        bool providerReturnConfirmed;
        bool renterReturnConfirmed;
        bool disputed;
        uint256 correctionCount;
        uint256 createdAt;
    }

    mapping(bytes32 => Rental) private rentals;
    mapping(bytes32 => bool) private rentalExists;

    error RentalAlreadyExists(bytes32 rentalId);
    error RentalNotFound(bytes32 rentalId);
    error InvalidAddress();
    error InvalidHash();
    error NotParticipant();
    error EvidenceHashMismatch();
    error AlreadyConfirmed();
    error HandoverNotCompleted();
    error ReturnAlreadyCompleted();
    error DisputeAlreadyFlagged();

    event RentalCreated(
        bytes32 indexed rentalId,
        address indexed provider,
        address indexed renter,
        bytes32 assetReferenceHash,
        uint256 timestamp
    );

    event HandoverAttested(
        bytes32 indexed rentalId,
        address indexed participant,
        bytes32 evidenceHash,
        uint256 timestamp
    );

    event HandoverCompleted(
        bytes32 indexed rentalId,
        bytes32 evidenceHash,
        uint256 timestamp
    );

    event ReturnAttested(
        bytes32 indexed rentalId,
        address indexed participant,
        bytes32 evidenceHash,
        uint256 timestamp
    );

    event ReturnCompleted(
        bytes32 indexed rentalId,
        bytes32 evidenceHash,
        uint256 timestamp
    );

    event DisputeFlagged(
        bytes32 indexed rentalId,
        address indexed raisedBy,
        uint256 timestamp
    );

    event CorrectionAppended(
        bytes32 indexed rentalId,
        uint256 indexed correctionNumber,
        bytes32 correctionHash,
        address indexed submittedBy,
        uint256 timestamp
    );

    /**
     * @notice Creates a rental record. The caller becomes the provider.
     * @param rentalId Unique, non-personal rental identifier.
     * @param assetReferenceHash Hash of a non-personal asset reference.
     * @param renter Wallet address of the renter.
     */
    function createRental(
        bytes32 rentalId,
        bytes32 assetReferenceHash,
        address renter
    ) external {
        if (rentalId == bytes32(0) || assetReferenceHash == bytes32(0)) {
            revert InvalidHash();
        }
        if (renter == address(0) || renter == msg.sender) {
            revert InvalidAddress();
        }
        if (rentalExists[rentalId]) {
            revert RentalAlreadyExists(rentalId);
        }

        rentals[rentalId] = Rental({
            provider: msg.sender,
            renter: renter,
            assetReferenceHash: assetReferenceHash,
            handoverEvidenceHash: bytes32(0),
            returnEvidenceHash: bytes32(0),
            providerHandoverConfirmed: false,
            renterHandoverConfirmed: false,
            providerReturnConfirmed: false,
            renterReturnConfirmed: false,
            disputed: false,
            correctionCount: 0,
            createdAt: block.timestamp
        });

        rentalExists[rentalId] = true;

        emit RentalCreated(
            rentalId,
            msg.sender,
            renter,
            assetReferenceHash,
            block.timestamp
        );
    }

    /**
     * @notice Provider and renter must submit the same handover evidence hash.
     *         The first confirmation fixes the hash; the second must match it.
     */
    function attestHandover(
        bytes32 rentalId,
        bytes32 evidenceHash
    ) external {
        _requireRental(rentalId);
        _requireParticipant(rentalId);

        if (evidenceHash == bytes32(0)) revert InvalidHash();

        Rental storage rental = rentals[rentalId];

        if (
            rental.providerHandoverConfirmed &&
            rental.renterHandoverConfirmed
        ) {
            revert AlreadyConfirmed();
        }

        if (rental.handoverEvidenceHash == bytes32(0)) {
            rental.handoverEvidenceHash = evidenceHash;
        } else if (rental.handoverEvidenceHash != evidenceHash) {
            revert EvidenceHashMismatch();
        }

        if (msg.sender == rental.provider) {
            if (rental.providerHandoverConfirmed) revert AlreadyConfirmed();
            rental.providerHandoverConfirmed = true;
        } else {
            if (rental.renterHandoverConfirmed) revert AlreadyConfirmed();
            rental.renterHandoverConfirmed = true;
        }

        emit HandoverAttested(
            rentalId,
            msg.sender,
            evidenceHash,
            block.timestamp
        );

        if (
            rental.providerHandoverConfirmed &&
            rental.renterHandoverConfirmed
        ) {
            emit HandoverCompleted(
                rentalId,
                evidenceHash,
                block.timestamp
            );
        }
    }

    /**
     * @notice Provider and renter must submit the same return evidence hash.
     *         Return confirmation is available only after handover is complete.
     */
    function attestReturn(
        bytes32 rentalId,
        bytes32 evidenceHash
    ) external {
        _requireRental(rentalId);
        _requireParticipant(rentalId);

        if (evidenceHash == bytes32(0)) revert InvalidHash();

        Rental storage rental = rentals[rentalId];

        if (
            !rental.providerHandoverConfirmed ||
            !rental.renterHandoverConfirmed
        ) {
            revert HandoverNotCompleted();
        }

        if (
            rental.providerReturnConfirmed &&
            rental.renterReturnConfirmed
        ) {
            revert ReturnAlreadyCompleted();
        }

        if (rental.returnEvidenceHash == bytes32(0)) {
            rental.returnEvidenceHash = evidenceHash;
        } else if (rental.returnEvidenceHash != evidenceHash) {
            revert EvidenceHashMismatch();
        }

        if (msg.sender == rental.provider) {
            if (rental.providerReturnConfirmed) revert AlreadyConfirmed();
            rental.providerReturnConfirmed = true;
        } else {
            if (rental.renterReturnConfirmed) revert AlreadyConfirmed();
            rental.renterReturnConfirmed = true;
        }

        emit ReturnAttested(
            rentalId,
            msg.sender,
            evidenceHash,
            block.timestamp
        );

        if (
            rental.providerReturnConfirmed &&
            rental.renterReturnConfirmed
        ) {
            emit ReturnCompleted(rentalId, evidenceHash, block.timestamp);
        }
    }

    /**
     * @notice Either participant can flag a dispute.
     *         This records a dispute; it does not decide who is at fault.
     */
    function flagDispute(bytes32 rentalId) external {
        _requireRental(rentalId);
        _requireParticipant(rentalId);

        Rental storage rental = rentals[rentalId];
        if (rental.disputed) revert DisputeAlreadyFlagged();

        rental.disputed = true;

        emit DisputeFlagged(rentalId, msg.sender, block.timestamp);
    }

    /**
     * @notice Appends a correction event without overwriting original evidence.
     *         The correction hash should refer to an off-chain correction record.
     */
    function appendCorrection(
        bytes32 rentalId,
        bytes32 correctionHash
    ) external {
        _requireRental(rentalId);
        _requireParticipant(rentalId);

        if (correctionHash == bytes32(0)) revert InvalidHash();

        Rental storage rental = rentals[rentalId];
        rental.correctionCount += 1;

        emit CorrectionAppended(
            rentalId,
            rental.correctionCount,
            correctionHash,
            msg.sender,
            block.timestamp
        );
    }

    function getRental(
        bytes32 rentalId
    ) external view returns (Rental memory) {
        _requireRental(rentalId);
        return rentals[rentalId];
    }

    function getStatus(
        bytes32 rentalId
    ) external view returns (RentalStatus) {
        _requireRental(rentalId);
        Rental storage rental = rentals[rentalId];

        if (rental.disputed) return RentalStatus.Disputed;

        if (
            rental.providerReturnConfirmed &&
            rental.renterReturnConfirmed
        ) {
            return RentalStatus.Returned;
        }

        if (
            rental.providerHandoverConfirmed &&
            rental.renterHandoverConfirmed
        ) {
            return RentalStatus.HandoverConfirmed;
        }

        return RentalStatus.Created;
    }

    function _requireRental(bytes32 rentalId) private view {
        if (!rentalExists[rentalId]) revert RentalNotFound(rentalId);
    }

    function _requireParticipant(bytes32 rentalId) private view {
        Rental storage rental = rentals[rentalId];

        if (
            msg.sender != rental.provider &&
            msg.sender != rental.renter
        ) {
            revert NotParticipant();
        }
    }
}
