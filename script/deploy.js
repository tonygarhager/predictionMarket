const { ethers } = require("hardhat");

async function main() {
    // Deploy the PredictionMarket contract
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    const Currency = '0x96d738c9Fd8Ab12d92ef215FE4cbd6A07F254799'
    const OOv2 = '0x9f1263B8f0355673619168b5B8c0248f1d03e88C'
    const PredictionMarket = await hre.ethers.getContractFactory("PredictionMarket");
    const predictionMarket = await PredictionMarket.deploy(Currency, OOv2);
    //await predictionMarket.deployed();
    console.log(predictionMarket.target);
    console.log("Waiting for 5 block confirmations...");
    //await predictionMarket.deployTransaction.wait(5);
    try {
        await hre.run("verify:verify", {
            address: predictionMarket.target,
            constructorArguments: [Currency, OOv2],
            contract: predictionMarket.artifact // "contract/PredictionMarket.sol:PredictionMarket"
        });
    } catch (error) {
        console.error("Verification failed:", error.message);
    }
}

main()