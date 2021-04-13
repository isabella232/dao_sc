const {expectEvent, expectRevert} = require('@openzeppelin/test-helpers');
const BN = web3.utils.BN;

const NoSwappingLiquidationStrategy = artifacts.require('NoSwappingLiquidationStrategy.sol');
const Pool = artifacts.require('Pool.sol');
const Token = artifacts.require('KyberNetworkTokenV2.sol');

const Helper = require('./helper.js');
const {zeroAddress, ethAddress} = require('./helper.js');

let admin;
let operator;
let treasuryPool;
let rewardPool;
let strategy;

contract('NoSwappingLiquiditionStrategy', function (accounts) {
  before('Global setup', async () => {
    admin = accounts[1];
    operator = accounts[4];
  });

  describe('#constructor', async () => {
    it('invalid params', async () => {
      await expectRevert(NoSwappingLiquidationStrategy.new(zeroAddress, accounts[0], accounts[0]), 'admin 0');
      await expectRevert(NoSwappingLiquidationStrategy.new(admin, zeroAddress, accounts[0]), 'invalid treasury pool');
      await expectRevert(NoSwappingLiquidationStrategy.new(admin, accounts[0], zeroAddress), 'invalid reward pool');
    });

    it('correct data inited', async () => {
      strategy = await NoSwappingLiquidationStrategy.new(admin, accounts[0], accounts[2]);
      Helper.assertEqual(admin, await strategy.admin());
      Helper.assertEqual(accounts[0], await strategy.treasuryPool());
      Helper.assertEqual(accounts[2], await strategy.rewardPool());
    });
  });

  describe('#update pool addresses', async () => {
    beforeEach('init data', async () => {
      strategy = await NoSwappingLiquidationStrategy.new(admin, accounts[0], accounts[2]);
    });

    it('treasury pool - reverts not admin', async () => {
      await expectRevert(strategy.updateTreasuryPool(accounts[2], {from: operator}), 'only admin');
    });

    it('treasury pool - reverts invalid reward pool', async () => {
      await expectRevert(strategy.updateTreasuryPool(zeroAddress, {from: admin}), 'invalid treasury pool');
    });

    it('treasury pool - data updates and events', async () => {
      let tx = await strategy.updateTreasuryPool(accounts[5], {from: admin});
      Helper.assertEqual(accounts[5], await strategy.treasuryPool());
      expectEvent(tx, 'TreasuryPoolSet', {
        treasuryPool: accounts[5],
      });
    });

    it('reward pool - reverts not admin', async () => {
      await expectRevert(strategy.updateRewardPool(accounts[2], {from: operator}), 'only admin');
    });

    it('reward pool - reverts invalid reward pool', async () => {
      await expectRevert(strategy.updateRewardPool(zeroAddress, {from: admin}), 'invalid reward pool');
    });

    it('reward pool - data updates and events', async () => {
      let tx = await strategy.updateRewardPool(accounts[5], {from: admin});
      Helper.assertEqual(accounts[5], await strategy.rewardPool());
      expectEvent(tx, 'RewardPoolSet', {
        rewardPool: accounts[5],
      });
    });
  });

  describe('#liquidate', async () => {
    let tokens = [];
    before('deploy tokens', async () => {
      treasuryPool = await Pool.new(admin, []);
      rewardPool = await Pool.new(admin, []);
      for (let i = 0; i < 4; i++) {
        let token = await Token.new();
        tokens.push(token);
      }
    });

    it('revert withdraw funds from treasury pool reverts', async () => {
      strategy = await NoSwappingLiquidationStrategy.new(admin, accounts[2], accounts[3]);
      await expectRevert.unspecified(strategy.liquidate([tokens[0].address], [10]));
    });

    it('correct event', async () => {
      strategy = await NoSwappingLiquidationStrategy.new(admin, treasuryPool.address, rewardPool.address);
      let ethAmount = new BN(10000);
      let tokenAmount = new BN(2000);
      await Helper.sendEtherWithPromise(accounts[0], treasuryPool.address, ethAmount);
      await tokens[0].transfer(treasuryPool.address, tokenAmount);
      let treasuryEthBal = await Helper.getBalancePromise(treasuryPool.address);
      let rewardEthBal = await Helper.getBalancePromise(rewardPool.address);
      let treasuryTokenBal = await tokens[0].balanceOf(treasuryPool.address);
      let rewardTokenBal = await tokens[0].balanceOf(rewardPool.address);
      await treasuryPool.authorizeStrategies([strategy.address], {from: admin});
      let tx = await strategy.liquidate([ethAddress, tokens[0].address], [ethAmount, tokenAmount], {
        from: accounts[4],
      });
      Helper.assertEqual(treasuryEthBal.sub(ethAmount), await Helper.getBalancePromise(treasuryPool.address));
      Helper.assertEqual(rewardEthBal.add(ethAmount), await Helper.getBalancePromise(rewardPool.address));
      Helper.assertEqual(treasuryTokenBal.sub(tokenAmount), await tokens[0].balanceOf(treasuryPool.address));
      Helper.assertEqual(rewardTokenBal.add(tokenAmount), await tokens[0].balanceOf(rewardPool.address));
      let hasEvent = false;
      for (let i = 0; i < tx.logs.length; i++) {
        if (tx.logs[i].event == 'Liquidated') {
          hasEvent = true;
          Helper.assertEqual(accounts[4], tx.logs[i].args.sender);
          Helper.assertEqualArray([ethAddress, tokens[0].address], tx.logs[i].args.sources);
          Helper.assertEqualArray([ethAmount, tokenAmount], tx.logs[i].args.amounts);
        }
      }
      assert(hasEvent);
    });
  });
});
