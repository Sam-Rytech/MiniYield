import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-verify'
require('dotenv').config()

export const solidity = {
  version: '0.8.19',
  settings: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
}
export const networks = {
  hardhat: {
    forking: {
      url: process.env.MAINNET_RPC_URL ||
        'https://eth-mainnet.alchemyapi.io/v2/your-api-key',
      blockNumber: 18500000,
    },
  },
  sepolia: {
    url: process.env.SEPOLIA_RPC_URL ||
      'https://sepolia.infura.io/v3/your-project-id',
    accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    gasPrice: 20000000000, // 20 gwei
  },
  baseSepolia: {
    url: 'https://sepolia.base.org',
    accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    gasPrice: 1000000000, // 1 gwei
  },
  base: {
    url: 'https://mainnet.base.org',
    accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
  },
}
export const etherscan = {
  apiKey: {
    sepolia: process.env.ETHERSCAN_API_KEY,
    base: process.env.BASESCAN_API_KEY,
    baseSepolia: process.env.BASESCAN_API_KEY,
  },
  customChains: [
    {
      network: 'base',
      chainId: 8453,
      urls: {
        apiURL: 'https://api.basescan.org/api',
        browserURL: 'https://basescan.org',
      },
    },
    {
      network: 'baseSepolia',
      chainId: 84532,
      urls: {
        apiURL: 'https://api-sepolia.basescan.org/api',
        browserURL: 'https://sepolia.basescan.org',
      },
    },
  ],
}
export const gasReporter = {
  enabled: process.env.REPORT_GAS !== undefined,
  currency: 'USD',
}
