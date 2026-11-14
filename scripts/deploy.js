import hre from "hardhat";

async function main() {
  // Uses the network selected by Hardhat CLI.
  // Without --network, this creates a temporary local simulation.
  const { ethers } = await hre.network.create();

  const [deployer] = await ethers.getSigners();

  console.log("Deploying ReturnProof contract...");
  console.log("Deployer:", deployer.address);

  const registry = await ethers.deployContract("RentalEvidenceRegistry");
  await registry.waitForDeployment();

  const contractAddress = await registry.getAddress();

  console.log("RentalEvidenceRegistry deployed to:", contractAddress);
  console.log("Network:", (await ethers.provider.getNetwork()).chainId.toString());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
