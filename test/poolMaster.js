const {expectEvent, expectRevert} = require('@openzeppelin/test-helpers');
const {assert} = require('chai');
const {hasNumericValueDependencies} = require('mathjs');
const Helper = require('./helper.js');

let BN;

let admin;
let operator;
let user;

let ZERO;
let ONE;
let MAX_UINT;
let BPS;
let MAX_FEE_BPS;
let MAX_FEE_BPS_PLUS_ONE;
let ZERO_BYTES;
let ethAddress = Helper.ethAddress;
let mintFeeBps;
let claimFeeBps;
let burnFeeBps;

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
    ONE = ethers.constants.One;
    BPS = new BN.from(10000);
    MAX_FEE_BPS = new BN.from(1000);
    MAX_FEE_BPS_PLUS_ONE = MAX_FEE_BPS.add(ONE);
    precisionUnits = new BN.from(10).pow(new BN.from(18));
    mintFeeBps = ZERO;
    claimFeeBps = new BN.from(5);
    burnFeeBps = new BN.from(10);

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
      mintFeeBps,
      claimFeeBps,
      burnFeeBps
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

  it('should allow changing of fees by admin only', async () => {
    await expectRevert(poolMaster.connect(operator).changeFees(15, 10, 5), 'only admin');
    await expectRevert(poolMaster.connect(user).changeFees(15, 10, 5), 'only admin');

    let tx = await (await poolMaster.connect(admin).changeFees(25, 20, 10)).wait();
    Helper.assertEqual((await poolMaster.getFeeRate(0)).toString(), 25);
    Helper.assertEqual((await poolMaster.getFeeRate(1)).toString(), 20);
    Helper.assertEqual((await poolMaster.getFeeRate(2)).toString(), 10);
    expectEvent({logs: tx.events}, 'FeesSet', {
      mintFeeBps: new BN.from(25),
      burnFeeBps: new BN.from(20),
      claimFeeBps: new BN.from(10),
    });
  });

  it('revert invalid fee changes', async () => {
    await expectRevert(poolMaster.connect(admin).changeFees(MAX_FEE_BPS_PLUS_ONE, ZERO, ZERO), 'bad mint bps');
    await expectRevert(poolMaster.connect(admin).changeFees(ZERO, MAX_FEE_BPS_PLUS_ONE, ZERO), 'bad claim bps');
    await expectRevert(poolMaster.connect(admin).changeFees(ZERO, ZERO, 9), 'bad burn bps');
    await expectRevert(poolMaster.connect(admin).changeFees(ZERO, ZERO, MAX_FEE_BPS_PLUS_ONE), 'bad burn bps');
  });

  it('should apply valid fee changes', async () => {
    await poolMaster.connect(admin).changeFees(MAX_FEE_BPS, ZERO, burnFeeBps);
    Helper.assertEqual((await poolMaster.getFeeRate(0)).toString(), MAX_FEE_BPS.toString());
    Helper.assertEqual((await poolMaster.getFeeRate(1)).toString(), ZERO.toString());
    Helper.assertEqual((await poolMaster.getFeeRate(2)).toString(), burnFeeBps.toString());

    await poolMaster.connect(admin).changeFees(ZERO, MAX_FEE_BPS, burnFeeBps);
    Helper.assertEqual((await poolMaster.getFeeRate(0)).toString(), ZERO.toString());
    Helper.assertEqual((await poolMaster.getFeeRate(1)).toString(), MAX_FEE_BPS.toString());
    Helper.assertEqual((await poolMaster.getFeeRate(2)).toString(), burnFeeBps.toString());

    await poolMaster.connect(admin).changeFees(ZERO, ZERO, MAX_FEE_BPS);
    Helper.assertEqual((await poolMaster.getFeeRate(0)).toString(), ZERO.toString());
    Helper.assertEqual((await poolMaster.getFeeRate(1)).toString(), ZERO.toString());
    Helper.assertEqual((await poolMaster.getFeeRate(2)).toString(), MAX_FEE_BPS.toString());
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

  it('should return 0 proRataKnc if totalSupply is 0', async () => {
    Helper.assertEqual((await poolMaster.getProRataKnc()).toString(), ZERO.toString());
  });

  it('should be able to vote by operator only', async () => {
    await expectRevert(poolMaster.connect(user).vote([1], [1]), 'only operator');
    await poolMaster.connect(admin).addOperator(operator.address);
    await poolMaster.connect(operator).vote([1], [1]);
    await poolMaster.connect(operator).vote([1, 2, 3], [1, 2, 3]);
  });

  it('should revert for incorrect lengths of proposal ids or bitmasks', async () => {
    await poolMaster.connect(admin).addOperator(operator.address);
    await expectRevert(poolMaster.connect(operator).vote([1], []), 'invalid length');
    await expectRevert(poolMaster.connect(operator).vote([], [1]), 'invalid length');
    await expectRevert(poolMaster.connect(operator).vote([1, 2], [1]), 'invalid length');
    await expectRevert(poolMaster.connect(operator).vote([1], [2, 1]), 'invalid length');
  });

  it('should be able to claim multiple tokens and restake KNC rewards by operator', async () => {
    let initialAdminFee = await poolMaster.withdrawableAdminFees();
    let initialEthBal = await ethers.provider.getBalance(poolMaster.address);
    let initialKncStake = await poolMaster.getLatestStake();
    await expectRevert(
      poolMaster.connect(user).claimReward(1, 1, [ethAddress, newKnc.address], [100000, 100000], [ZERO_BYTES]),
      'only operator'
    );

    await poolMaster.connect(admin).addOperator(operator.address);
    await poolMaster.connect(operator).claimReward(1, 1, [ethAddress, newKnc.address], [100000, 100000], [ZERO_BYTES]);
    let adminFee = await poolMaster.withdrawableAdminFees();
    let ethBal = await ethers.provider.getBalance(poolMaster.address);
    let kncStake = await poolMaster.getLatestStake();
    Helper.assertGreater(adminFee.toString(), initialAdminFee.toString());
    Helper.assertGreater(ethBal.toString(), initialEthBal.toString());
    Helper.assertGreater(kncStake.toString(), initialKncStake.toString());
  });

  it('should be able to claim rewards even if claimable KNC is 0', async () => {
    let initialEthBal = await ethers.provider.getBalance(poolMaster.address);
    await poolMaster.connect(admin).addOperator(operator.address);
    await poolMaster.connect(operator).claimReward(1, 1, [ethAddress, newKnc.address], [100000, 0], [ZERO_BYTES]);
    let ethBal = await ethers.provider.getBalance(poolMaster.address);
    Helper.assertGreater(ethBal.toString(), initialEthBal.toString());
  });

  it('should have pool master give token allowance to proxy by the operator', async () => {
    await expectRevert(poolMaster.connect(user).approveKyberProxyContract(dai.address, true), 'only operator');
    await expectRevert(poolMaster.connect(operator).approveKyberProxyContract(dai.address, true), 'only operator');
    await poolMaster.connect(admin).addOperator(operator.address);
    await poolMaster.connect(operator).approveKyberProxyContract(dai.address, true);
    Helper.assertEqual(MAX_UINT.toString(), (await dai.allowance(poolMaster.address, kyberProxy.address)).toString());
    await poolMaster.connect(operator).approveKyberProxyContract(dai.address, false);
    Helper.assertEqual(ZERO.toString(), (await dai.allowance(poolMaster.address, kyberProxy.address)).toString());
  });

  it('should revert attempts to give new KNC allowance to kyber proxy', async () => {
    await poolMaster.connect(admin).addOperator(operator.address);
    await expectRevert(
      poolMaster.connect(operator).approveKyberProxyContract(newKnc.address, true),
      'knc not allowed'
    );
    await expectRevert(
      poolMaster.connect(operator).approveKyberProxyContract(newKnc.address, false),
      'knc not allowed'
    );
  });

  it('should be able to liquidate rewards to KNC and re-stake by operator', async () => {
    await poolMaster.connect(admin).addOperator(operator.address);
    // send dai, eth and knc to pool master
    let tokenAmount = precisionUnits.mul(new BN.from(2));
    await newKnc.connect(admin).mint(poolMaster.address, tokenAmount);
    await admin.sendTransaction({to: poolMaster.address, value: tokenAmount});
    await dai.transfer(poolMaster.address, tokenAmount);

    await expectRevert(poolMaster.connect(user).liquidateTokensToKnc([dai.address], [ZERO]), 'only operator');
    let initialAdminFee = await poolMaster.withdrawableAdminFees();
    let initialKncStake = await poolMaster.getLatestStake();

    // liquidate ETH
    await poolMaster.connect(operator).liquidateTokensToKnc([ethAddress], [ZERO]);
    adminFee = await poolMaster.withdrawableAdminFees();
    kncStake = await poolMaster.getLatestStake();
    Helper.assertGreater(adminFee.toString(), initialAdminFee.toString());
    Helper.assertGreater(kncStake.toString(), initialKncStake.toString());
    Helper.assertEqual((await ethers.provider.getBalance(poolMaster.address)).toString(), ONE.toString());
    initialAdminFee = adminFee;
    initialKncStake = kncStake;

    // liquidate DAI
    await poolMaster.connect(operator).approveKyberProxyContract(dai.address, true);
    await poolMaster.connect(operator).liquidateTokensToKnc([dai.address], [ZERO]);
    adminFee = await poolMaster.withdrawableAdminFees();
    kncStake = await poolMaster.getLatestStake();
    Helper.assertGreater(adminFee.toString(), initialAdminFee.toString());
    Helper.assertGreater(kncStake.toString(), initialKncStake.toString());
    Helper.assertEqual((await dai.balanceOf(poolMaster.address)).toString(), ONE.toString());
  });

  it('should revert liquidations for bad token and minRates length', async () => {
    await poolMaster.connect(admin).addOperator(operator.address);
    await expectRevert(poolMaster.connect(operator).liquidateTokensToKnc([dai.address], []), 'unequal lengths');
  });

  it('will stake any leftover knc through liquidations', async () => {
    await poolMaster.connect(admin).addOperator(operator.address);
    // someone accidentally send KNC to contract
    await newKnc.connect(admin).mint(poolMaster.address, precisionUnits);
    let adminFee = await poolMaster.withdrawableAdminFees();
    let kncStake = await poolMaster.getLatestStake();
    await poolMaster.connect(operator).liquidateTokensToKnc([newKnc.address], [ZERO]);
    Helper.assertGreater((await poolMaster.withdrawableAdminFees()).toString(), adminFee.toString());
    Helper.assertGreater((await poolMaster.getLatestStake()).toString(), kncStake.toString());
  });

  it('should withdraw admin fee by operator only to admin', async () => {
    let initialKncBal = await newKnc.balanceOf(admin.address);
    await poolMaster.connect(admin).addOperator(operator.address);
    await poolMaster.connect(operator).claimReward(1, 1, [newKnc.address], [100000], [ZERO_BYTES]);
    let adminFee = await poolMaster.withdrawableAdminFees();

    await expectRevert(poolMaster.withdrawAdminFee(), 'only operator');
    await poolMaster.connect(operator).withdrawAdminFee();

    Helper.assertEqual(
      (await newKnc.balanceOf(admin.address)).toString(),
      initialKncBal.add(adminFee).sub(ONE).toString()
    );
    Helper.assertEqual((await poolMaster.withdrawableAdminFees()).toString(), ONE.toString());
  });

  it('should stake admin fee by operator only to admin', async () => {
    let initialPoolBal = await poolMaster.balanceOf(admin.address);
    await poolMaster.connect(admin).addOperator(operator.address);
    await poolMaster.connect(operator).claimReward(1, 1, [newKnc.address], [100000], [ZERO_BYTES]);

    await expectRevert(poolMaster.stakeAdminFee(), 'only operator');
    await poolMaster.connect(operator).stakeAdminFee();

    Helper.assertGreater((await poolMaster.balanceOf(admin.address)).toString(), initialPoolBal.toString());
    Helper.assertEqual((await poolMaster.withdrawableAdminFees()).toString(), ONE.toString());
  });

  it('should fail attempted withdrawals if user does not have sufficient tokens', async () => {
    await expectRevert(poolMaster.connect(operator).withdraw(1000), 'insufficient balance');
  });

  it('should redeem more KNC staked after rewards have been claimed and re-staked', async () => {
    let userTotalStakeAmount = precisionUnits.mul(new BN.from(2));
    let stakeAmount = precisionUnits;
    let proRataKnc = await poolMaster.getProRataKnc();
    await poolMaster.connect(admin).addOperator(operator.address);
    // stake 1 old and 1 new KNC
    await oldKnc.connect(user).approve(poolMaster.address, MAX_UINT);
    await poolMaster.connect(user).depositWithOldKnc(stakeAmount);

    await newKnc.connect(admin).mint(user.address, stakeAmount);
    await newKnc.connect(user).approve(poolMaster.address, MAX_UINT);
    await poolMaster.connect(user).depositWithNewKnc(stakeAmount);

    // verify pool master has KNC staked into DAO
    Helper.assertGreater((await poolMaster.getLatestStake()).toString(), ZERO.toString());

    // admin stakes some KNC so that proRataKnc > 0
    await newKnc.connect(admin).approve(poolMaster.address, MAX_UINT);
    await newKnc.connect(admin).mint(admin.address, stakeAmount);
    await poolMaster.connect(admin).depositWithNewKnc(stakeAmount);

    // claim ETH, KNC, and DAI rewards from reward distributor
    await poolMaster
      .connect(operator)
      .claimReward(1, 1, [ethAddress, newKnc.address, dai.address], [50000, 50000, 50000], [ZERO_BYTES]);

    // before liquidation, if user withdraw, should obtain more KNC than stake (minus burn fee)
    let userKncBalBefore = await newKnc.balanceOf(user.address);
    await poolMaster.connect(user).approve(poolMaster.address, MAX_UINT);
    await poolMaster.connect(user).withdraw(await poolMaster.balanceOf(user.address));
    let userKncBalAfter = await newKnc.balanceOf(user.address);
    Helper.assertGreater(
      userKncBalAfter.sub(userKncBalBefore).toString(),
      userTotalStakeAmount.mul(BPS.sub(burnFeeBps)).div(BPS).toString()
    );

    Helper.assertGreater((await poolMaster.getProRataKnc()).toString, proRataKnc.toString());
    proRataKnc = await poolMaster.getProRataKnc();

    // restake
    userTotalStakeAmount = userKncBalAfter.sub(userKncBalBefore);
    await poolMaster.connect(user).depositWithNewKnc(userTotalStakeAmount);
    userKncBalBefore = await newKnc.balanceOf(user.address);

    // after liquidation, if user withdraw, should obtain more KNC than stake (minus burn fee)
    await poolMaster.connect(operator).approveKyberProxyContract(dai.address, true);
    await poolMaster.connect(operator).liquidateTokensToKnc([ethAddress, dai.address], [ZERO, ZERO]);
    await poolMaster.connect(user).withdraw(await poolMaster.balanceOf(user.address));
    userKncBalAfter = await newKnc.balanceOf(user.address);
    Helper.assertGreater(
      userKncBalAfter.sub(userKncBalBefore).toString(),
      userTotalStakeAmount.mul(BPS.sub(burnFeeBps)).div(BPS).toString()
    );
    Helper.assertGreater((await poolMaster.getProRataKnc()).toString, proRataKnc.toString());
  });
});
