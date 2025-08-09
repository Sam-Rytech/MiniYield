const hre = require('hardhat')

async function main() {
  const deploymentFile = `deployment-${hre.network.name}.json`

  try {
    const fs = require('fs')
    const deployment = JSON.parse(fs.readFileSync(deploymentFile, 'utf8'))

    console.log('🔍 Verifying contracts on', hre.network.name)

    // Verify MiniYield
    console.log('Verifying MiniYield...')
    await hre.run('verify:verify', {
      address: deployment.contracts.MiniYield,
      constructorArguments: [],
    })

    console.log('✅ All contracts verified!')
  } catch (error) {
    if (error.message.includes('Already Verified')) {
      console.log('✅ Contract already verified!')
    } else {
      console.error('❌ Verification failed:', error.message)
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
