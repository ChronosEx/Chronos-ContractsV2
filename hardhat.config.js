require("@nomiclabs/hardhat-waffle");

require('@openzeppelin/hardhat-upgrades');

require("@nomiclabs/hardhat-etherscan");


require("@nomiclabs/hardhat-web3");

const { PRIVATEKEY, TESTPRIVATEKEY, APIKEY } = require("./pvkey.js")

module.exports = {
  // latest Solidity version
  solidity: {
    compilers: [
      {
        version: "0.8.13",
        settings: {
          optimizer: {
            enabled: true,
            runs: 650,
          },
        },
      },
    ]
  },
  defaultNetwork: 'arbitrumOne',

  networks: {

    arbitrumOne: {
      url: "https://arb1.arbitrum.io/rpc",
      chainId: 42161,
      accounts: PRIVATEKEY
    },

    hardhat: {
      forking: {
          url: "https://arb1.arbitrum.io/rpc",
          chainId: 42161,
      },
      //accounts: []
    }
  
  },

  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/

    apiKey: {
      arbitrumOne: APIKEY[0],
    }
  },

  mocha: {
    timeout: 100000000
  }

}