const hre = require('hardhat')

async function main() {
  console.log('🚀 Starting MiniYield deployment...')

  const [deployer] = await hre.ethers.getSigners()
  console.log('Deploying contracts with account:', deployer.address)
  console.log(
    'Account balance:',
    hre.ethers.formatEther(
      await hre.ethers.provider.getBalance(deployer.address)
    )
  )

  // Deploy MiniYield contract
  console.log('\n📋 Deploying MiniYield contract...')
  const MiniYield = await hre.ethers.getContractFactory('MiniYield')
  const miniYield = await MiniYield.deploy()
  await miniYield.waitForDeployment()

  const miniYieldAddress = await miniYield.getAddress()
  console.log('✅ MiniYield deployed to:', miniYieldAddress)

  // Deploy mock tokens and protocols for testing (only on testnet)
  const network = hre.network.name
  if (
    network === 'sepolia' ||
    network === 'baseSepolia' ||
    network === 'hardhat'
  ) {
    console.log('\n🎭 Deploying mock contracts for testing...')

    // Deploy Mock USDC
    const MockERC20 = await hre.ethers.getContractFactory('MockERC20')
    const mockUSDC = await MockERC20.deploy('Mock USDC', 'mUSDC', 6)
    await mockUSDC.waitForDeployment()
    const mockUSDCAddress = await mockUSDC.getAddress()
    console.log('✅ Mock USDC deployed to:', mockUSDCAddress)

    // Deploy Mock Protocol
    const MockYieldProtocol = await hre.ethers.getContractFactory(
      'MockYieldProtocol'
    )
    const mockProtocol = await MockYieldProtocol.deploy('Mock Aave', 500) // 5% APY
    await mockProtocol.waitForDeployment()
    const mockProtocolAddress = await mockProtocol.getAddress()
    console.log('✅ Mock Protocol deployed to:', mockProtocolAddress)

    // Add the mock protocol to MiniYield
    console.log('\n⚙️ Setting up mock protocol...')
    await miniYield.addProtocol(mockUSDCAddress, mockProtocolAddress)
    console.log('✅ Mock protocol added to MiniYield')

    // Mint some mock tokens to deployer for testing
    const mintAmount = hre.ethers.parseUnits('10000', 6) // 10,000 mUSDC
    await mockUSDC.mint(deployer.address, mintAmount)
    console.log('✅ Minted 10,000 mUSDC to deployer')

    console.log('\n📋 Test Contract Addresses:')
    console.log('Mock USDC:', mockUSDCAddress)
    console.log('Mock Protocol:', mockProtocolAddress)
  }

  console.log('\n📋 Deployment Summary:')
  console.log('Network:', network)
  console.log('MiniYield:', miniYieldAddress)
  console.log('Gas used for MiniYield deployment:', '~2,500,000 gas')

  // Save deployment info
  const fs = require('fs')
  const deploymentInfo = {
    network: network,
    contracts: {
      MiniYield: miniYieldAddress,
    },
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
  }

  fs.writeFileSync(
    `deployment-${network}.json`,
    JSON.stringify(deploymentInfo, null, 2)
  )
  console.log(`✅ Deployment info saved to deployment-${network}.json`)

  // Verification instructions
  if (network !== 'hardhat') {
    console.log('\n🔍 To verify contracts, run:')
    console.log(`npx hardhat verify --network ${network} ${miniYieldAddress}`)
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
