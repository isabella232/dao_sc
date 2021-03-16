const {expectEvent, expectRevert} = require('@openzeppelin/test-helpers');
const BN = web3.utils.BN;

const LiquidationStrategy = artifacts.require('LiquidationStrategy.sol');
const Token = artifacts.require('KyberNetworkTokenV2.sol');
const Pool = artifacts.require('Pool.sol');
const NonePayableContract = artifacts.require('NonePayableContract.sol');

const Helper = require('./helper.js');
const {zeroAddress, ethAddress, ProposalState} = require('./helper.js');

let admin;
let operators;
let pool;
let strategy;

contract('LiquidationStrategy', function (accounts) {
  before('Global setup', async () => {
    admin = accounts[1];
    operators = [accounts[2], accounts[3]];
    strategies = [accounts[4], accounts[5]];
    pool = await Pool.new(admin, strategies);
  });

  describe('#constructor', async () => {
    it('revert invalid params', async () => {
      await expectRevert(
        LiquidationStrategy.new(
          zeroAddress, accounts[0], accounts[1], 1000, 100, 100, []
        ),
        'admin 0'
      );

      await expectRevert(
        LiquidationStrategy.new(
          admin, zeroAddress, accounts[1], 1000, 100, 100, []
        ),
        'invalid treasury pool'
      );

      await expectRevert(
        LiquidationStrategy.new(
          admin, accounts[0], zeroAddress, 1000, 100, 100, []
        ),
        'invalid reward pool'
      );
    });

    it('correct data initialized', async () => {
      let strategy = await LiquidationStrategy.new(
        admin, accounts[2], accounts[4], 100, 200, 300, [accounts[5], accounts[6]]
      );
      Helper.assertEqual(admin, await strategy.admin());
      Helper.assertEqual(accounts[2], await strategy.treasuryPool());
      Helper.assertEqual(accounts[4], await strategy.rewardPool());
      Helper.assertEqual(true, await strategy.isWhitelistedToken(accounts[5]));
      Helper.assertEqual(true, await strategy.isWhitelistedToken(accounts[6]));
      Helper.assertEqual(2, await strategy.getWhitelistedTokensLength());
      Helper.assertEqual(accounts[5], await strategy.getWhitelistedTokenAt(0));
      Helper.assertEqual(accounts[6], await strategy.getWhitelistedTokenAt(1));
      Helper.assertEqual([accounts[5], accounts[6]], await strategy.getAllWhitelistedTokens());
      Helper.assertEqual(false, await strategy.isWhitelistLiquidatorEnabled());
    });
  });

  describe('#update pools', async () => {
    before('init contract', async () => {
      strategy = await LiquidationStrategy.new(
        admin, accounts[1], accounts[2], 100, 200, 300, []
      );
    });

    it('fee pool - revert not admin', async () => {
      await expectRevert(
        strategy.updateTreasuryPool(accounts[2], { from: accounts[0] }),
        'only admin'
      )
    });

    it('fee pool - revert invalid address', async () => {
      await expectRevert(
        strategy.updateTreasuryPool(zeroAddress, { from: admin }),
        'invalid treasury pool'
      )
    });

    it('fee pool - test event', async () => {
      let tx = await strategy.updateTreasuryPool(accounts[0], { from: admin });
      Helper.assertEqual(accounts[0], await strategy.treasuryPool());
      expectEvent(tx, 'TreasuryPoolSet', {
        treasuryPool: accounts[0]
      });
      tx = await strategy.updateTreasuryPool(accounts[1], { from: admin });
      Helper.assertEqual(accounts[1], await strategy.treasuryPool());
      expectEvent(tx, 'TreasuryPoolSet', {
        treasuryPool: accounts[1]
      });
    });

    it('treasury pool - revert not admin', async () => {
      await expectRevert(
        strategy.updateRewardPool(accounts[2], { from: accounts[0] }),
        'only admin'
      )
    });

    it('treasury pool - revert invalid address', async () => {
      await expectRevert(
        strategy.updateRewardPool(zeroAddress, { from: admin }),
        'invalid reward pool'
      )
    });

    it('treasury pool - test event', async () => {
      let tx = await strategy.updateRewardPool(accounts[0], { from: admin });
      Helper.assertEqual(accounts[0], await strategy.rewardPool());
      expectEvent(tx, 'RewardPoolSet', {
        rewardPool: accounts[0]
      });
      tx = await strategy.updateRewardPool(accounts[1], { from: admin });
      Helper.assertEqual(accounts[1], await strategy.rewardPool());
      expectEvent(tx, 'RewardPoolSet', {
        rewardPool: accounts[1]
      });
    });
  });

  describe('#whitelisted tokens', async () => {

  });

  describe('#whitelisted liquidator', async () => {
  })
});
