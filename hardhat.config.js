require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require('hardhat-contract-sizer');
require('@openzeppelin/hardhat-upgrades');

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints accounts", async (_, { web3 }) => {
  console.log(await web3.eth.getAccounts());
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

const fs = require('fs');
const key = fs.readFileSync(".secret").toString().trim();
const infura = fs.readFileSync(".infura").toString().trim();
const escan = fs.readFileSync(".etherscan").toString().trim();
const pscan = fs.readFileSync(".polygonscan").toString().trim();

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
    },
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${infura}`,
      accounts: [`0x${key}`]
    },
    goerli: {
      url: `https://goerli.infura.io/v3/${infura}`,
      accounts: [`0x${key}`]
    },
    polygonMumbai: {
      url: `https://polygon-mumbai.infura.io/v3/${infura}`,
      accounts: [`0x${key}`]
    }
  },
  etherscan: {
    apiKey: {
      rinkeby: `${escan}`,
      goerli: `${escan}`,
      polygonMumbai: `${pscan}`,
      polygon: `${pscan}`
    }
  },
  solidity: {
    version: "0.8.7",
    settings: {
      optimizer: {
        enabled: true,
        runs: 10000
      }
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 40000
  }
};
