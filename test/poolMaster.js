const {expectRevert} = require('@openzeppelin/test-helpers');
const {assert} = require('chai');
const Helper = require('./helper.js');

let BN;

let admin;
let operator;
let user;

let ZERO;
let MAX_UINT;
let ZERO_BYTES;
let ethAddress = Helper.ethAddress;

let oldKnc;
let newKnc;
let dai;

let kyberProxy;
let kyberGovernance;
let kyberStaking;
let rewardsDistributor;

let precisionUnits;

contract('PoolMaster', function () {
  before('Global setup', async () => {
    [user, operator, admin] = await ethers.getSigners();

    // constants
    BN = ethers.BigNumber;
    MAX_UINT = ethers.constants.MaxUint256;
    ZERO_BYTES = ethers.constants.HashZero;
    ZERO = ethers.constants.Zero;
    precisionUnits = new BN.from(10).pow(new BN.from(18));

    let Token = await ethers.getContractFactory('KyberNetworkTokenV2');
    oldKnc = await Token.deploy();
    await oldKnc.deployed();

    Token = await ethers.getContractFactory('MockToken');
    dai = await Token.deploy('DAI', 'DAI', new BN.from(100000000).mul(precisionUnits));
    await dai.deployed();

    let NewKNC = await ethers.getContractFactory('MockKyberTokenV2');
    newKnc = await upgrades.deployProxy(NewKNC, [oldKnc.address, admin.address]);
    await newKnc.deployed();

    let KyberProxy = await ethers.getContractFactory('MockSimpleKyberProxy');
    kyberProxy = await KyberProxy.deploy();
    await kyberProxy.deployed();
    await kyberProxy.setKncAddress(newKnc.address);

    let KyberGovernance = await ethers.getContractFactory('MockSimpleKyberGovernance');
    kyberGovernance = await KyberGovernance.deploy();
    await kyberGovernance.deployed();

    let KyberStaking = await ethers.getContractFactory('MockKyberStaking');
    kyberStaking = await KyberStaking.deploy(
      admin.address,
      newKnc.address,
      86400,
      100 + (await Helper.getCurrentBlockTime())
    );
    await kyberStaking.deployed();

    let RewardsDistributor = await ethers.getContractFactory('MockSimpleRewardDistributor');
    rewardsDistributor = await RewardsDistributor.deploy();
    await rewardsDistributor.deployed();

    // transfer some old KNC to operator and admin
    let initialBalance = new BN.from(100000).mul(precisionUnits);
    await oldKnc.transfer(operator.address, initialBalance);
    await oldKnc.transfer(admin.address, initialBalance);

    // mint some new KNC to kyber proxy
    await newKnc.connect(admin).mint(kyberProxy.address, initialBalance);

    // transfer some new KNC, ETH and DAI to reward distributor
    await newKnc.connect(admin).mint(rewardsDistributor.address, initialBalance);
    await admin.sendTransaction({to: rewardsDistributor.address, value: precisionUnits.mul(new BN.from(10))});
    await dai.transfer(rewardsDistributor.address, initialBalance);
  });

  beforeEach('deploy poolMaster contract', async () => {
    let PoolMaster = await ethers.getContractFactory('PoolMaster');
    poolMaster = await PoolMaster.connect(admin).deploy(
      'Pool KNC',
      'PKNC',
      kyberProxy.address,
      kyberStaking.address,
      kyberGovernance.address,
      rewardsDistributor.address,
      5
    );
    await poolMaster.deployed();
  });

  it('should allow changing of proxy by admin only', async () => {
    await expectRevert(poolMaster.connect(operator).changeKyberProxy(admin.address), 'only admin');
    await expectRevert(poolMaster.connect(user).changeKyberProxy(admin.address), 'only admin');

    await poolMaster.connect(admin).changeKyberProxy(admin.address);
    Helper.assertEqual(await poolMaster.kyberProxy(), admin.address);
  });

  it('should allow changing of rewards distributor by admin only', async () => {
    await expectRevert(poolMaster.connect(operator).changeRewardsDistributor(admin.address), 'only admin');
    await expectRevert(poolMaster.connect(user).changeRewardsDistributor(admin.address), 'only admin');

    await poolMaster.connect(admin).changeRewardsDistributor(admin.address);
    Helper.assertEqual(await poolMaster.rewardsDistributor(), admin.address);
  });

  it('should allow changing of rewards distributor by admin only', async () => {
    await expectRevert(poolMaster.connect(operator).changeGovernance(admin.address), 'only admin');
    await expectRevert(poolMaster.connect(user).changeGovernance(admin.address), 'only admin');

    await poolMaster.connect(admin).changeGovernance(admin.address);
    Helper.assertEqual(await poolMaster.kyberGovernance(), admin.address);
  });

  it('should allow changing of rewards fee by admin only', async () => {
    await expectRevert(poolMaster.connect(operator).changeAdminFee(15), 'only admin');
    await expectRevert(poolMaster.connect(user).changeAdminFee(15), 'only admin');

    await poolMaster.connect(admin).changeAdminFee(15);
    Helper.assertEqual((await poolMaster.adminFeeBps()).toString(), 15);
  });

  it('should allow addition of operators by admin only', async () => {
    await expectRevert(poolMaster.connect(operator).addOperator(operator.address), 'only admin');
    await expectRevert(poolMaster.connect(user).addOperator(operator.address), 'only admin');

    await poolMaster.connect(admin).addOperator(operator.address);
    assert.isTrue(await poolMaster.isOperator(operator.address));
  });

  it('should allow removal of operators by admin only', async () => {
    await poolMaster.connect(admin).addOperator(operator.address);
    await expectRevert(poolMaster.connect(operator).removeOperator(operator.address), 'only admin');
    await expectRevert(poolMaster.connect(user).removeOperator(operator.address), 'only admin');

    await poolMaster.connect(admin).removeOperator(operator.address);
    assert.isFalse(await poolMaster.isOperator(operator.address));
  });

  it('should allow for staking with old KNC', async () => {
    let tokenAmount = 1000;
    await oldKnc.connect(user).approve(poolMaster.address, MAX_UINT);
    let kncBalBefore = await oldKnc.balanceOf(user.address);
    await poolMaster.connect(user).depositWithOldKnc(tokenAmount);

    // check old knc balance decreased
    let expectedKncBal = kncBalBefore.sub(new BN.from(tokenAmount));
    let actualKncBal = await oldKnc.balanceOf(user.address);
    Helper.assertEqual(expectedKncBal.toString(), actualKncBal.toString());

    // check knc stake increased
    Helper.assertEqual((await poolMaster.getLatestStake()).toString(), tokenAmount);

    // check PKNC minted to user
    Helper.assertGreater((await poolMaster.balanceOf(user.address)).toString(), 0);
  });

  it('should allow for staking with new KNC', async () => {
    // user migrate his old KNC
    let tokenAmount = 1000;
    await oldKnc.connect(user).approve(newKnc.address, MAX_UINT);
    await newKnc.connect(user).mintWithOldKnc(tokenAmount);
    await newKnc.connect(user).approve(poolMaster.address, MAX_UINT);
    let currentPKNCBal = await poolMaster.balanceOf(user.address);
    await poolMaster.connect(user).depositWithNewKnc(1000);

    // check knc stake increased
    Helper.assertEqual((await poolMaster.getLatestStake()).toString(), tokenAmount);

    // check PKNC minted to user
    Helper.assertGreater((await poolMaster.balanceOf(user.address)).toString(), currentPKNCBal.toString());
  });

  it('should be able to vote by admin or operator only', async () => {
    await expectRevert(poolMaster.connect(user).vote(1, 1), 'only admin or operator');
    await poolMaster.connect(admin).addOperator(operator.address);
    await poolMaster.connect(admin).vote(1, 1);
    await poolMaster.connect(operator).vote(1, 1);
  });

  it('should be able to claim multiple tokens and restake KNC rewards by admin or operator', async () => {
    let initialAdminFee = await poolMaster.withdrawableAdminFees();
    let initialEthBal = await ethers.provider.getBalance(poolMaster.address);
    let initialKncStake = await poolMaster.getLatestStake();
    await expectRevert(
      poolMaster.connect(user).claimReward(1, 1, [ethAddress, newKnc.address], [1000, 1000], [ZERO_BYTES]),
      'only admin or operator'
    );

    await poolMaster.connect(admin).addOperator(operator.address);
    await poolMaster.connect(operator).claimReward(1, 1, [ethAddress, newKnc.address], [1000, 1000], [ZERO_BYTES]);

    let adminFee = await poolMaster.withdrawableAdminFees();
    let ethBal = await ethers.provider.getBalance(poolMaster.address);
    let kncStake = await poolMaster.getLatestStake();
    Helper.assertGreater(adminFee.toString(), initialAdminFee.toString());
    Helper.assertGreater(ethBal.toString(), initialEthBal.toString());
    Helper.assertGreater(kncStake.toString(), initialKncStake.toString());

    initialAdminFee = adminFee;
    initialEthBal = ethBal;
    initialKncStake = kncStake;

    await poolMaster.connect(admin).claimReward(1, 1, [ethAddress, newKnc.address], [1000, 1000], [ZERO_BYTES]);

    adminFee = await poolMaster.withdrawableAdminFees();
    ethBal = await ethers.provider.getBalance(poolMaster.address);
    kncStake = await poolMaster.getLatestStake();
    Helper.assertGreater(adminFee.toString(), initialAdminFee.toString());
    Helper.assertGreater(ethBal.toString(), initialEthBal.toString());
    Helper.assertGreater(kncStake.toString(), initialKncStake.toString());
  });

  it('should have pool master give token allowance to proxy by the admin or operator', async () => {
    await expectRevert(
      poolMaster.connect(user).approveKyberProxyContract(dai.address, true),
      'only admin or operator'
    );
    await expectRevert(
      poolMaster.connect(operator).approveKyberProxyContract(dai.address, true),
      'only admin or operator'
    );
    await poolMaster.connect(admin).addOperator(operator.address);
    await poolMaster.connect(operator).approveKyberProxyContract(dai.address, true);
    Helper.assertEqual(MAX_UINT.toString(), (await dai.allowance(poolMaster.address, kyberProxy.address)).toString());
    await poolMaster.connect(admin).approveKyberProxyContract(dai.address, false);
    Helper.assertEqual(ZERO.toString(), (await dai.allowance(poolMaster.address, kyberProxy.address)).toString());
  });

  it('should be able to liquidate rewards to KNC and re-stake by admin or operator', async () => {
    await poolMaster.connect(admin).addOperator(operator.address);
    // send dai, eth and knc to pool master
    let tokenAmount = precisionUnits.mul(new BN.from(2));
    await newKnc.connect(admin).mint(poolMaster.address, tokenAmount);
    await admin.sendTransaction({to: poolMaster.address, value: tokenAmount});
    await dai.transfer(poolMaster.address, tokenAmount);

    await expectRevert(poolMaster.connect(user).liquidateTokensToKnc([dai.address], [ZERO]), 'only admin or operator');

    let initialAdminFee = await poolMaster.withdrawableAdminFees();
    let initialKncStake = await poolMaster.getLatestStake();

    // liquidate ETH
    await poolMaster.connect(operator).liquidateTokensToKnc([ethAddress], [ZERO]);
    adminFee = await poolMaster.withdrawableAdminFees();
    kncStake = await poolMaster.getLatestStake();
    Helper.assertGreater(adminFee.toString(), initialAdminFee.toString());
    Helper.assertGreater(kncStake.toString(), initialKncStake.toString());
    Helper.assertEqual((await ethers.provider.getBalance(poolMaster.address)).toString(), ZERO.toString());
    initialAdminFee = adminFee;
    initialKncStake = kncStake;

    // liquidate DAI
    await poolMaster.connect(operator).approveKyberProxyContract(dai.address, true);
    await poolMaster.connect(admin).liquidateTokensToKnc([dai.address], [ZERO]);
    adminFee = await poolMaster.withdrawableAdminFees();
    kncStake = await poolMaster.getLatestStake();
    Helper.assertGreater(adminFee.toString(), initialAdminFee.toString());
    Helper.assertGreater(kncStake.toString(), initialKncStake.toString());
    Helper.assertEqual((await dai.balanceOf(poolMaster.address)).toString(), ZERO.toString());
  });

  it('should withdraw admin fee by anyone to admin', async () => {
    let initialKncBal = await newKnc.balanceOf(admin.address);
    await poolMaster.connect(admin).addOperator(operator.address);
    await poolMaster.connect(operator).claimReward(1, 1, [newKnc.address], [1000], [ZERO_BYTES]);
    let adminFee = await poolMaster.withdrawableAdminFees();
    await poolMaster.withdrawAdminFee();

    Helper.assertEqual((await newKnc.balanceOf(admin.address)).toString(), initialKncBal.add(adminFee).toString());
    Helper.assertEqual((await poolMaster.withdrawableAdminFees()).toString(), ZERO.toString());
  });

  it('should redeem more KNC staked after rewards have been claimed and re-staked', async () => {
    let userTotalStakeAmount = precisionUnits.mul(new BN.from(2));
    let stakeAmount = precisionUnits;
    await poolMaster.connect(admin).addOperator(operator.address);
    // stake 1 old and 1 new KNC
    await oldKnc.connect(user).approve(poolMaster.address, MAX_UINT);
    await poolMaster.connect(user).depositWithOldKnc(stakeAmount);

    await newKnc.connect(admin).mint(user.address, stakeAmount);
    await newKnc.connect(user).approve(poolMaster.address, MAX_UINT);
    await poolMaster.connect(user).depositWithNewKnc(stakeAmount);

    // verify pool master has KNC staked into DAO
    Helper.assertGreater((await poolMaster.getLatestStake()).toString(), ZERO.toString());

    // claim ETH, KNC, and DAI rewards from reward distributor
    await poolMaster
      .connect(operator)
      .claimReward(1, 1, [ethAddress, newKnc.address, dai.address], [500, 500, 500], [ZERO_BYTES]);

    // before liquidation, if user withdraw, should obtain more KNC than stake
    let userKncBalBefore = await newKnc.balanceOf(user.address);
    await poolMaster.connect(user).approve(poolMaster.address, MAX_UINT);
    await poolMaster.connect(user).withdraw(await poolMaster.balanceOf(user.address));
    let userKncBalAfter = await newKnc.balanceOf(user.address);
    Helper.assertGreater(userKncBalAfter.sub(userKncBalBefore).toString(), userTotalStakeAmount.toString());

    // restake
    userTotalStakeAmount = userKncBalAfter.sub(userKncBalBefore);
    await poolMaster.connect(user).depositWithNewKnc(userTotalStakeAmount);
    userKncBalBefore = await newKnc.balanceOf(user.address);

    // after liquidation, if user withdraw, should obtain more KNC than stake
    await poolMaster.approveKyberProxyContract(dai.address, true);
    await poolMaster.connect(operator).liquidateTokensToKnc([ethAddress, dai.address], [ZERO, ZERO]);
    await poolMaster.connect(user).withdraw(await poolMaster.balanceOf(user.address));
    userKncBalAfter = await newKnc.balanceOf(user.address);
    Helper.assertGreater(userKncBalAfter.sub(userKncBalBefore).toString(), userTotalStakeAmount.toString());
  });
});
