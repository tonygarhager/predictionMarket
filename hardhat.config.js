require("@nomicfoundation/hardhat-toolbox");

const dotenv = require('dotenv')

dotenv.config()

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    // hardhat: {
    //   forking: {
    //     url: 'https://site1.moralis-nodes.com/polygon/',
    //   }
    // },
    localhost: {
      url:'http://127.0.0.1:8545/'	// <-- here add the '/' in the end
    },
    sepolia: {
      url: 'https://sepolia.infura.io/v3/d8200853cc4c4001956d0c1a2d0de540',
      chainId: 11155111,
      accounts: [`${process.env.DEPLOYER_KEY}`],
      gasMultiplier: 2
    },
    // mainnet: {
    //   url: 'https://eth-mainnet.nodereal.io/v1/1659dfb40aa24bbb8153a677b98064d7',
    //   accounts: [``],
    //   chainId: 1,
    // },
    // polygon: {
    //   url: 'https://rpc.ankr.com/polygon',
    //   // accounts: [`${mnemonic}`],
    //   chainId: 137,
    // },
  },
  etherscan: {
    apiKey: {
      sepolia: "C7MSIMK1FXRGYMB39IHUURH68KIEVDPUH2",
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.5.7"
      },
      {
        version: "0.6.12"
      },
      {
        version: '0.8.0',
      },
      {
        version: '0.8.16',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          },
        }
      },
      {
        version: '0.8.27',
      },
    ]
  },
  paths: {
    sources: './contracts',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts'
  },
};
