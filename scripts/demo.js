
import hre from "hardhat";

async function main() {
    const { ethers } = await hre.network.connect();

    console.log("\n=================================");
    console.log("       RETURNPROOF DEMO");
    console.log("=================================\n");

    // Get two participants
    const [provider, renter] = await ethers.getSigners();

    console.log("Provider:", provider.address);
    console.log("Renter:", renter.address);

    // Deploy the smart contract
    const Registry = await ethers.getContractFactory(
        "RentalEvidenceRegistry"
    );

    const registry = await Registry.deploy();
    await registry.waitForDeployment();

    console.log("\nContract deployed:", await registry.getAddress());

    // Helper for readable status
    const statuses = [
        "Created",
        "Handover Confirmed",
        "Returned",
        "Disputed"
    ];

    // RENTAL 1: Complete rental lifecycle
    console.log("\n--- RENTAL 1 ---");

    const rentalId = ethers.id("rental-demo-001");
    const assetHash = ethers.id("camera-asset-001");
    const handoverHash = ethers.id("handover-photo-001");
    const returnHash = ethers.id("return-photo-001");
    const correctionHash = ethers.id("correction-note-001");

    // 1. Create rental
    await (await registry.connect(provider).createRental(
        rentalId,
        assetHash,
        renter.address
    )).wait();

    console.log("1. Rental created");

    // 2. Confirm handover
    await (await registry.connect(provider).attestHandover(
        rentalId,
        handoverHash
    )).wait();

    console.log("2. Provider confirmed handover");

    await (await registry.connect(renter).attestHandover(
        rentalId,
        handoverHash
    )).wait();

    console.log("3. Renter confirmed handover");

    let status = await registry.getStatus(rentalId);
    console.log("Status:", statuses[Number(status)]);

    // 3. Confirm return
    await (await registry.connect(provider).attestReturn(
        rentalId,
        returnHash
    )).wait();

    console.log("4. Provider confirmed return");

    await (await registry.connect(renter).attestReturn(
        rentalId,
        returnHash
    )).wait();

    console.log("5. Renter confirmed return");

    status = await registry.getStatus(rentalId);
    console.log("Status:", statuses[Number(status)]);

    // 4. Append correction
    await (await registry.connect(provider).appendCorrection(
        rentalId,
        correctionHash
    )).wait();

    console.log("6. Correction appended");

    const rental = await registry.getRental(rentalId);
    console.log("Correction count:", rental.correctionCount.toString());

    // RENTAL 2: Dispute demonstration
    console.log("\n--- RENTAL 2: DISPUTE ---");

    const rentalId2 = ethers.id("rental-demo-002");
    const assetHash2 = ethers.id("tool-asset-002");

    await (await registry.connect(provider).createRental(
        rentalId2,
        assetHash2,
        renter.address
    )).wait();

    console.log("1. Second rental created");

    await (await registry.connect(renter).flagDispute(
        rentalId2
    )).wait();

    console.log("2. Renter flagged a dispute");

    status = await registry.getStatus(rentalId2);
    console.log("Final status:", statuses[Number(status)]);

    console.log("\n=================================");
    console.log("       DEMO COMPLETED");
    console.log("=================================\n");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});