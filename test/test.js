const { ethers } = require("hardhat")

const globals = {}

describe("Prediction", () => {
    describe("Deployment", () => {
        it("Currency", async () => {
            const [addr1] = await ethers.getSigners()
            // const _Currency = await ethers.getContractFactory("USDC")
            // const Currency = await _Currency.deploy()
            // globals.Currency = Currency
            const Currency = await ethers.getContractAt("USDC", "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")

            // await Currency.connect(owner).transfer(addr1.address, ethers.parseUnits("10000", 6))

            const nonce = await Currency.nonces("0x421A4a3Ac89167B63b8F8Ed57D0a2c16f2ec7D24")
            console.log('nonce', nonce)
            const Permit = [
                { name: 'owner', type: 'address' },
                { name: 'spender', type: 'address' },
                { name: 'value', type: 'uint256' },
                { name: 'nonce', type: 'uint256' },
                { name: 'deadline', type: 'uint256' },
            ]
            const deadline = Math.floor(Date.now() / 1000 + 20000)
            const message = {
                owner: "0x421A4a3Ac89167B63b8F8Ed57D0a2c16f2ec7D24",
                spender: addr1.address,
                value: ethers.parseEther("100").toString(),
                nonce: String(Number(nonce)),
                deadline
            }
            const signature = await addr1.signTypedData({
                name: 'USDC',
                version: '1',
                chainId: 1,
                verifyingContract: Currency.target,
            }, {
                Permit,
            }, message)
            const { v, r, s } = ethers.Signature.from(signature)
            // await Currency.permit(addr1.address, addr2.address, ethers.parseEther("100"), deadline, v, r, s)
            // await Currency.connect(addr2).transferFrom(addr1.address, addr2.address, ethers.parseEther("100"))
            // console.log(ethers.formatEther(await Currency.allowance(addr1.address, addr2.address)))
        })
        // it("Sandbox", async () => {
        //     const _Sandbox = await ethers.getContractFactory("OracleSandbox")
        //     const Sandbox = await _Sandbox.deploy(globals.Currency.target)
        //     globals.finder = await Sandbox.finder()
        //     globals.oo = await Sandbox.oo()
        // })
        // it("Market", async () => {
        //     const _Market = await ethers.getContractFactory("PredictionMarket")
        //     globals.Market = await _Market.deploy(globals.finder, globals.Currency.target, globals.oo)
        // })
    })

    // describe("Market", () => {
    //     let marketId, token1, token2
    //     it("initialize", async () => {
    //         const [owner, addr1, addr2] = await ethers.getSigners()
    //         const { Market, Currency } = globals
    //         await Currency.approve(Market.target, ethers.MaxUint256)
    //         const tx = await (await Market.initializeMarket("Red", "Blue", "Which team wins?", ethers.parseEther("100"), ethers.parseEther("10"))).wait()
    //         const args = tx.logs.find(log => log.fragment?.name==='MarketInitialized')?.args
    //         [marketId, _, _, _, token1, token2] = args
    //         // console.log(owner.address, ethers.formatEther(await Currency.balanceOf(owner.address)))
    //         // console.log(Market.target, ethers.formatEther(await Currency.balanceOf(Market.target)))
    //     })
    //     it("create", async () => {
    //         const { Market, Currency } = globals
    //         await Market.createOutcomeTokens(marketId, ethers.parseEther("1"))
    //         console.log()
    //     })
    // })
})