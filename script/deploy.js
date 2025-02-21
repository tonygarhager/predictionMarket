const { ethers } = require("hardhat");

async function main() {
    const Currency = '0x96d738c9Fd8Ab12d92ef215FE4cbd6A07F254799'
    const OOv3 = '0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944'
    const _PredictionMarket = await ethers.getContractFactory("PredictionMarket");
    const PredictionMarket = await _PredictionMarket.deploy(Currency, OOv3);
    console.log(PredictionMarket.target)
    await hre.run("verify:verify", {
        address: PredictionMarket.target,
        constructorArguments: [Currency, OOv3],
        contract: PredictionMarket.artifact // "contract/PredictionMarket.sol:PredictionMarket"
    })
}

main()