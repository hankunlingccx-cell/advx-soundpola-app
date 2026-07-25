const hre = require("hardhat");

async function main() {
  const operatorAddress = process.env.OPERATOR_ADDRESS;

  console.log("Deploying SoundPolaNFT...");
  const Factory = await hre.ethers.getContractFactory("SoundPolaNFT");
  const contract = await Factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log(`SoundPolaNFT deployed at: ${address}`);

  if (operatorAddress) {
    console.log(`Setting operator ${operatorAddress} as minter...`);
    const tx = await contract.setMinter(operatorAddress, true);
    await tx.wait();
    console.log("Operator set as minter.");
  }

  console.log(`\nNetwork: ${hre.network.name}`);
  console.log(`Contract: ${address}`);
  console.log(`\nSet BACKEND_CHAIN_CONTRACT_ADDRESS=${address} in your backend .env`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
