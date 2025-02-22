const { ethers } = require("hardhat");

async function main() {
    const Currency = '0x96d738c9Fd8Ab12d92ef215FE4cbd6A07F254799'
    const OOv2 = '0x9f1263B8f0355673619168b5B8c0248f1d03e88C'
    const _PredictionMarket = await ethers.getContractFactory("PredictionMarket");
    const PredictionMarket = await _PredictionMarket.deploy(Currency, OOv2);
    console.log(PredictionMarket.target)
    await hre.run("verify:verify", {
        address: PredictionMarket.target,
        constructorArguments: [Currency, OOv2],
        contract: PredictionMarket.artifact // "contract/PredictionMarket.sol:PredictionMarket"
    })
}

main()