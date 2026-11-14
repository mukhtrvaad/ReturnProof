import { expect } from "chai";
import hre from "hardhat";

const { ethers } = await hre.network.create();

describe("RentalEvidenceRegistry", function () {
  let registry;
  let provider;
  let renter;
  let outsider;

  const rentalId = ethers.id("rental-001");
  const assetHash = ethers.id("asset-camera-001");
  const handoverHash = ethers.id("handover-evidence-v1");
  const returnHash = ethers.id("return-evidence-v1");
  const correctionHash = ethers.id("correction-note-v1");

  async function createSampleRental() {
    return registry
      .connect(provider)
      .createRental(rentalId, assetHash, renter.address);
  }

  async function completeHandover() {
    await registry.connect(provider).attestHandover(rentalId, handoverHash);
    await registry.connect(renter).attestHandover(rentalId, handoverHash);
  }

  beforeEach(async function () {
    [provider, renter, outsider] = await ethers.getSigners();
    registry = await ethers.deployContract("RentalEvidenceRegistry");
  });

  it("1. allows a provider to create a rental record", async function () {
    await expect(createSampleRental()).to.emit(registry, "RentalCreated");

    const rental = await registry.getRental(rentalId);

    expect(rental.provider).to.equal(provider.address);
    expect(rental.renter).to.equal(renter.address);
    expect(rental.assetReferenceHash).to.equal(assetHash);
  });

  it("2. rejects duplicate rental identifiers", async function () {
    await createSampleRental();

    await expect(
      registry
        .connect(provider)
        .createRental(rentalId, assetHash, renter.address)
    ).to.be.revertedWithCustomError(registry, "RentalAlreadyExists");
  });

  it("3. rejects handover confirmation from a non-participant", async function () {
    await createSampleRental();

    await expect(
      registry.connect(outsider).attestHandover(rentalId, handoverHash)
    ).to.be.revertedWithCustomError(registry, "NotParticipant");
  });

  it("4. requires both parties to confirm the same handover evidence", async function () {
    await createSampleRental();

    await registry.connect(provider).attestHandover(rentalId, handoverHash);

    let rental = await registry.getRental(rentalId);
    expect(rental.providerHandoverConfirmed).to.equal(true);
    expect(rental.renterHandoverConfirmed).to.equal(false);

    await expect(
      registry
        .connect(renter)
        .attestHandover(rentalId, ethers.id("different-evidence"))
    ).to.be.revertedWithCustomError(registry, "EvidenceHashMismatch");

    await registry.connect(renter).attestHandover(rentalId, handoverHash);

    rental = await registry.getRental(rentalId);
    expect(rental.providerHandoverConfirmed).to.equal(true);
    expect(rental.renterHandoverConfirmed).to.equal(true);
    expect(await registry.getStatus(rentalId)).to.equal(1n);
  });

  it("5. does not allow return confirmation before handover is complete", async function () {
    await createSampleRental();

    await expect(
      registry.connect(provider).attestReturn(rentalId, returnHash)
    ).to.be.revertedWithCustomError(registry, "HandoverNotCompleted");
  });

  it("6. records return only after both parties confirm the same evidence", async function () {
    await createSampleRental();
    await completeHandover();

    await registry.connect(provider).attestReturn(rentalId, returnHash);
    await registry.connect(renter).attestReturn(rentalId, returnHash);

    const rental = await registry.getRental(rentalId);

    expect(rental.providerReturnConfirmed).to.equal(true);
    expect(rental.renterReturnConfirmed).to.equal(true);
    expect(rental.returnEvidenceHash).to.equal(returnHash);
    expect(await registry.getStatus(rentalId)).to.equal(2n);
  });

  it("7. allows a participant to flag a dispute without deleting evidence", async function () {
    await createSampleRental();
    await completeHandover();

    await expect(registry.connect(renter).flagDispute(rentalId))
      .to.emit(registry, "DisputeFlagged");

    const rental = await registry.getRental(rentalId);

    expect(rental.disputed).to.equal(true);
    expect(rental.handoverEvidenceHash).to.equal(handoverHash);
    expect(await registry.getStatus(rentalId)).to.equal(3n);
  });

  it("8. appends a correction while preserving the original evidence hash", async function () {
    await createSampleRental();
    await completeHandover();

    await expect(
      registry.connect(provider).appendCorrection(rentalId, correctionHash)
    ).to.emit(registry, "CorrectionAppended");

    const rental = await registry.getRental(rentalId);

    expect(rental.handoverEvidenceHash).to.equal(handoverHash);
    expect(rental.correctionCount).to.equal(1n);
  });
});
