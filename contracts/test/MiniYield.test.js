import { expect } from 'chai'
import { ethers } from 'hardhat'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'

describe('MiniYield', function () {
  async function deployMiniYieldFixture() {
    const [owner, user1, user2, feeCollector] = await ethers.getSigners()

    // Deploy a mock ERC20 token
    const MockERC20 = await ethers.getContractFactory('MockERC20')
    const mockToken = await MockERC20.deploy('Mock USDC', 'mUSDC', 6)

    // Deploy MiniYield contract
    const MiniYield = await ethers.getContractFactory('MiniYield')
    const miniYield = await MiniYield.deploy()

    // Deploy mock protocol
    const MockProtocol = await ethers.getContractFactory('MockYieldProtocol')
    const mockProtocol = await MockProtocol.deploy('Mock Protocol', 5000) // 5% APY

    // Mint tokens to users for testing
    const mintAmount = ethers.parseUnits('1000', 6) // 1000 mUSDC
    await mockToken.mint(user1.address, mintAmount)
    await mockToken.mint(user2.address, mintAmount)

    return {
      miniYield,
      mockToken,
      mockProtocol,
      owner,
      user1,
      user2,
      feeCollector,
      mintAmount,
    }
  }

  describe('Deployment', function () {
    it('Should set the right owner', async function () {
      const { miniYield, owner } = await loadFixture(deployMiniYieldFixture)
      expect(await miniYield.owner()).to.equal(owner.address)
    })

    it('Should start unpaused', async function () {
      const { miniYield } = await loadFixture(deployMiniYieldFixture)
      expect(await miniYield.paused()).to.equal(false)
    })

    it('Should have zero supported tokens initially', async function () {
      const { miniYield } = await loadFixture(deployMiniYieldFixture)
      const tokens = await miniYield.getSupportedTokens()
      expect(tokens.length).to.equal(0)
    })
  })

  describe('Protocol Management', function () {
    it('Should add protocol for a token', async function () {
      const { miniYield, mockToken, mockProtocol, owner } = await loadFixture(
        deployMiniYieldFixture
      )

      await miniYield
        .connect(owner)
        .addProtocol(
          await mockToken.getAddress(),
          await mockProtocol.getAddress()
        )

      const protocolCount = await miniYield.getProtocolCount(
        await mockToken.getAddress()
      )
      expect(protocolCount).to.equal(1)

      const supportedTokens = await miniYield.getSupportedTokens()
      expect(supportedTokens).to.include(await mockToken.getAddress())
    })

    it('Should not allow non-owner to add protocol', async function () {
      const { miniYield, mockToken, mockProtocol, user1 } = await loadFixture(
        deployMiniYieldFixture
      )

      await expect(
        miniYield
          .connect(user1)
          .addProtocol(
            await mockToken.getAddress(),
            await mockProtocol.getAddress()
          )
      ).to.be.revertedWith('Ownable: caller is not the owner')
    })
  })

  describe('Deposits', function () {
    it('Should allow user to deposit tokens', async function () {
      const { miniYield, mockToken, mockProtocol, owner, user1 } =
        await loadFixture(deployMiniYieldFixture)

      // Setup protocol
      await miniYield
        .connect(owner)
        .addProtocol(
          await mockToken.getAddress(),
          await mockProtocol.getAddress()
        )

      // User approves and deposits
      const depositAmount = ethers.parseUnits('100', 6)
      await mockToken
        .connect(user1)
        .approve(await miniYield.getAddress(), depositAmount)

      await expect(
        miniYield
          .connect(user1)
          .deposit(await mockToken.getAddress(), depositAmount)
      )
        .to.emit(miniYield, 'Deposit')
        .withArgs(
          user1.address,
          await mockToken.getAddress(),
          depositAmount,
          await ethers.provider.getBlock().then((b) => b.timestamp + 1)
        )

      // Check user balance
      const userBalance = await miniYield.userBalances(
        user1.address,
        await mockToken.getAddress()
      )
      expect(userBalance.totalDeposited).to.equal(depositAmount)
      expect(userBalance.shares).to.equal(depositAmount) // 1:1 for first deposit
    })

    it('Should reject deposit of unsupported token', async function () {
      const { miniYield, mockToken, user1 } = await loadFixture(
        deployMiniYieldFixture
      )

      const depositAmount = ethers.parseUnits('100', 6)
      await mockToken
        .connect(user1)
        .approve(await miniYield.getAddress(), depositAmount)

      await expect(
        miniYield
          .connect(user1)
          .deposit(await mockToken.getAddress(), depositAmount)
      ).to.be.revertedWith('Token not supported')
    })

    it('Should reject zero amount deposit', async function () {
      const { miniYield, mockToken, mockProtocol, owner, user1 } =
        await loadFixture(deployMiniYieldFixture)

      await miniYield
        .connect(owner)
        .addProtocol(
          await mockToken.getAddress(),
          await mockProtocol.getAddress()
        )

      await expect(
        miniYield.connect(user1).deposit(await mockToken.getAddress(), 0)
      ).to.be.revertedWith('Amount must be greater than 0')
    })
  })

  describe('Withdrawals', function () {
    it('Should allow user to withdraw deposited tokens', async function () {
      const { miniYield, mockToken, mockProtocol, owner, user1 } =
        await loadFixture(deployMiniYieldFixture)

      // Setup and deposit
      await miniYield
        .connect(owner)
        .addProtocol(
          await mockToken.getAddress(),
          await mockProtocol.getAddress()
        )
      const depositAmount = ethers.parseUnits('100', 6)
      await mockToken
        .connect(user1)
        .approve(await miniYield.getAddress(), depositAmount)
      await miniYield
        .connect(user1)
        .deposit(await mockToken.getAddress(), depositAmount)

      // Withdraw
      const withdrawAmount = ethers.parseUnits('50', 6)
      await expect(
        miniYield
          .connect(user1)
          .withdraw(await mockToken.getAddress(), withdrawAmount)
      )
        .to.emit(miniYield, 'Withdraw')
        .withArgs(
          user1.address,
          await mockToken.getAddress(),
          withdrawAmount,
          await ethers.provider.getBlock().then((b) => b.timestamp + 1)
        )

      // Check remaining balance
      const userTotalValue = await miniYield.getUserTotalValue(
        user1.address,
        await mockToken.getAddress()
      )
      expect(userTotalValue).to.be.closeTo(
        depositAmount - withdrawAmount,
        ethers.parseUnits('1', 4) // Allow small rounding error
      )
    })

    it('Should reject withdrawal with no balance', async function () {
      const { miniYield, mockToken, mockProtocol, owner, user1 } =
        await loadFixture(deployMiniYieldFixture)

      await miniYield
        .connect(owner)
        .addProtocol(
          await mockToken.getAddress(),
          await mockProtocol.getAddress()
        )

      await expect(
        miniYield
          .connect(user1)
          .withdraw(await mockToken.getAddress(), ethers.parseUnits('100', 6))
      ).to.be.revertedWith('No balance to withdraw')
    })
  })

  describe('Share Calculation', function () {
    it('Should calculate shares correctly for first deposit', async function () {
      const { miniYield, mockToken, mockProtocol, owner } = await loadFixture(
        deployMiniYieldFixture
      )

      await miniYield
        .connect(owner)
        .addProtocol(
          await mockToken.getAddress(),
          await mockProtocol.getAddress()
        )

      const depositAmount = ethers.parseUnits('100', 6)
      const shares = await miniYield.calculateShares(
        await mockToken.getAddress(),
        depositAmount
      )
      expect(shares).to.equal(depositAmount)
    })

    it('Should calculate proportional shares for subsequent deposits', async function () {
      const { miniYield, mockToken, mockProtocol, owner, user1, user2 } =
        await loadFixture(deployMiniYieldFixture)

      // Setup
      await miniYield
        .connect(owner)
        .addProtocol(
          await mockToken.getAddress(),
          await mockProtocol.getAddress()
        )

      // First user deposits
      const firstDeposit = ethers.parseUnits('100', 6)
      await mockToken
        .connect(user1)
        .approve(await miniYield.getAddress(), firstDeposit)
      await miniYield
        .connect(user1)
        .deposit(await mockToken.getAddress(), firstDeposit)

      // Second user deposits same amount
      const secondDeposit = ethers.parseUnits('100', 6)
      await mockToken
        .connect(user2)
        .approve(await miniYield.getAddress(), secondDeposit)
      await miniYield
        .connect(user2)
        .deposit(await mockToken.getAddress(), secondDeposit)

      // Both users should have equal shares since they deposited same amount with no yield
      const user1Balance = await miniYield.userBalances(
        user1.address,
        await mockToken.getAddress()
      )
      const user2Balance = await miniYield.userBalances(
        user2.address,
        await mockToken.getAddress()
      )

      expect(user1Balance.shares).to.equal(user2Balance.shares)
    })
  })

  describe('Protocol Switching', function () {
    it('Should allow owner to switch protocols', async function () {
      const { miniYield, mockToken, mockProtocol, owner, user1 } =
        await loadFixture(deployMiniYieldFixture)

      // Deploy second protocol
      const MockProtocol2 = await ethers.getContractFactory('MockYieldProtocol')
      const mockProtocol2 = await MockProtocol2.deploy('Mock Protocol 2', 7000) // 7% APY

      // Setup protocols
      await miniYield
        .connect(owner)
        .addProtocol(
          await mockToken.getAddress(),
          await mockProtocol.getAddress()
        )
      await miniYield
        .connect(owner)
        .addProtocol(
          await mockToken.getAddress(),
          await mockProtocol2.getAddress()
        )

      // User deposits
      const depositAmount = ethers.parseUnits('100', 6)
      await mockToken
        .connect(user1)
        .approve(await miniYield.getAddress(), depositAmount)
      await miniYield
        .connect(user1)
        .deposit(await mockToken.getAddress(), depositAmount)

      // Switch protocol
      await expect(
        miniYield.connect(owner).switchProtocol(await mockToken.getAddress(), 1)
      ).to.emit(miniYield, 'ProtocolSwitch')

      // Verify active protocol changed
      const [activeProtocol] = await miniYield.getActiveProtocol(
        await mockToken.getAddress()
      )
      expect(activeProtocol).to.equal(await mockProtocol2.getAddress())
    })

    it('Should not allow non-owner to switch protocols', async function () {
      const { miniYield, mockToken, mockProtocol, owner, user1 } =
        await loadFixture(deployMiniYieldFixture)

      await miniYield
        .connect(owner)
        .addProtocol(
          await mockToken.getAddress(),
          await mockProtocol.getAddress()
        )

      await expect(
        miniYield.connect(user1).switchProtocol(await mockToken.getAddress(), 0)
      ).to.be.revertedWith('Ownable: caller is not the owner')
    })
  })

  describe('Admin Functions', function () {
    it('Should allow owner to pause and unpause', async function () {
      const { miniYield, owner } = await loadFixture(deployMiniYieldFixture)

      // Pause
      await miniYield.connect(owner).pause()
      expect(await miniYield.paused()).to.equal(true)

      // Unpause
      await miniYield.connect(owner).unpause()
      expect(await miniYield.paused()).to.equal(false)
    })

    it('Should not allow non-owner to pause', async function () {
      const { miniYield, user1 } = await loadFixture(deployMiniYieldFixture)

      await expect(miniYield.connect(user1).pause()).to.be.revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('Should reject deposits when paused', async function () {
      const { miniYield, mockToken, mockProtocol, owner, user1 } =
        await loadFixture(deployMiniYieldFixture)

      // Setup
      await miniYield
        .connect(owner)
        .addProtocol(
          await mockToken.getAddress(),
          await mockProtocol.getAddress()
        )
      await miniYield.connect(owner).pause()

      // Try to deposit
      const depositAmount = ethers.parseUnits('100', 6)
      await mockToken
        .connect(user1)
        .approve(await miniYield.getAddress(), depositAmount)

      await expect(
        miniYield
          .connect(user1)
          .deposit(await mockToken.getAddress(), depositAmount)
      ).to.be.revertedWith('Contract is paused')
    })
  })
})
