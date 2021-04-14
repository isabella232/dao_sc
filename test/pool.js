const {expectEvent, expectRevert} = require('@openzeppelin/test-helpers');
const BN = web3.utils.BN;

const Pool = artifacts.require('Pool.sol');
const Token = artifacts.require('KyberNetworkTokenV2.sol');
const NonePayableContract = artifacts.require('NonePayableContract.sol');

const Helper = require('./helper.js');
const {zeroAddress, ethAddress, ProposalState} = require('./helper.js');

let admin;
let operators;
let pool;
let strategies;

contract('Pool', function (accounts) {
  before('Global setup', async () => {
    admin = accounts[1];
    operators = [accounts[2], accounts[3]];
    strategies = [accounts[4], accounts[5]];
    pool = await Pool.new(admin, strategies);
  });

  const verifyStrategyData = async (strategies) => {
    Helper.assertEqual(strategies.length, await pool.getAuthorizedStrategiesLength());
    for (let i = 0; i < strategies.length; i++) {
      Helper.assertEqual(true, await pool.isAuthorizedStrategy(strategies[i]));
      Helper.assertEqual(strategies[i], await pool.getAuthorizedStrategyAt(i));
    }
    Helper.assertEqualArray(strategies, await pool.getAllAuthorizedStrategies());
  };

  describe('#constructor tests', async () => {
    it('invalid admin', async () => {
      await expectRevert((pool = Pool.new(zeroAddress, strategies)), 'admin 0');
    });

    it('invalid strategy', async () => {
      let newStrategies = [zeroAddress, accounts[1]];
      await expectRevert((pool = Pool.new(admin, newStrategies)), 'invalid strategy');
    });

    it('duplicated strategy', async () => {
      let newStrategies = [accounts[1], accounts[1]];
      await expectRevert((pool = Pool.new(admin, newStrategies)), 'only unauthorized strategy');
    });

    it('correct init data', async () => {
      pool = await Pool.new(admin, strategies);
      Helper.assertEqual(admin, await pool.admin());
      Helper.assertEqual(false, await pool.isPaused());
      await verifyStrategyData(strategies);
    });
  });

  describe('#authorizedStrategy', async () => {
    beforeEach('deploy pool', async () => {
      pool = await Pool.new(admin, strategies);
    });

    it('reverts not admin', async () => {
      await expectRevert(pool.authorizeStrategies([accounts[0]], {from: accounts[0]}), 'only admin');
    });

    it('reverts invalid strategy', async () => {
      await expectRevert(pool.authorizeStrategies([zeroAddress], {from: admin}), 'invalid strategy');
    });

    it('reverts only unauthorized strategy', async () => {
      let strategies = await pool.getAllAuthorizedStrategies();
      let newStrategies = [accounts[5]];
      for (let i = 0; i < strategies.length; i++) {
        newStrategies.push(strategies[i]);
      }
      await expectRevert(pool.authorizeStrategies(strategies, {from: admin}), 'only unauthorized strategy');
    });

    it('authorize empty array', async () => {
      let curStrategies = await pool.getAllAuthorizedStrategies();
      await pool.authorizeStrategies([], {from: admin});
      await verifyStrategyData(curStrategies);
    });

    it('authorize correct data records and events', async () => {
      let curStrategies = await pool.getAllAuthorizedStrategies();
      await pool.unauthorizeStrategies(strategies, {from: admin});
      await verifyStrategyData([]);
      let tx = await pool.authorizeStrategies(curStrategies, {from: admin});

      await verifyStrategyData(curStrategies);
      for (let id = 0; id < tx.receipt.logs.length; id++) {
        Helper.assertEqual('AuthorizedStrategy', tx.receipt.logs[id].event);
        Helper.assertEqual(curStrategies[id], tx.receipt.logs[id].args[0]);
      }
    });
  });

  describe('#unauthorizedStrategy', async () => {
    beforeEach('deploy pool', async () => {
      pool = await Pool.new(admin, strategies);
    });

    it('reverts not admin', async () => {
      await expectRevert(pool.unauthorizeStrategies([accounts[0]], {from: accounts[0]}), 'only admin');
    });

    it('reverts invalid strategy', async () => {
      await expectRevert(pool.unauthorizeStrategies([zeroAddress], {from: admin}), 'invalid strategy');
    });

    it('reverts only authorized strategy', async () => {
      let strategies = await pool.getAllAuthorizedStrategies();
      await pool.unauthorizeStrategies(strategies, {from: admin});
      await expectRevert(pool.unauthorizeStrategies(strategies, {from: admin}), 'only authorized strategy');
    });

    it('unauthorize empty array', async () => {
      let curStrategies = await pool.getAllAuthorizedStrategies();
      await pool.unauthorizeStrategies([], {from: admin});
      await verifyStrategyData(curStrategies);
    });

    it('unauthorize correct data records and events', async () => {
      let curStrategies = await pool.getAllAuthorizedStrategies();
      let tx = await pool.unauthorizeStrategies(curStrategies, {from: admin});
      await verifyStrategyData([]);
      for (let id = 0; id < tx.receipt.logs.length; id++) {
        Helper.assertEqual('UnauthorizedStrategy', tx.receipt.logs[id].event);
        Helper.assertEqual(curStrategies[id], tx.receipt.logs[id].args[0]);
      }
    });
  });

  describe('#pause & unpause', async () => {
    it('pause - revert not operator', async () => {
      await expectRevert(pool.pause({from: accounts[0]}), 'only operator');
    });

    it('pause - records data and event', async () => {
      await pool.addOperator(accounts[0], {from: admin});
      let tx = await pool.pause({from: accounts[0]});
      expectEvent(tx, 'Paused', {
        sender: accounts[0],
      });
      Helper.assertEqual(true, await pool.isPaused());

      // duplicated action, but still allowed
      tx = await pool.pause({from: accounts[0]});
      expectEvent(tx, 'Paused', {
        sender: accounts[0],
      });
      Helper.assertEqual(true, await pool.isPaused());
      await pool.removeOperator(accounts[0], {from: admin});
    });

    it('unpause - revert not admin', async () => {
      await expectRevert(pool.unpause({from: accounts[0]}), 'only admin');
      await pool.addOperator(accounts[0], {from: admin});
      await expectRevert(pool.unpause({from: accounts[0]}), 'only admin');
      await pool.removeOperator(accounts[0], {from: admin});
    });

    it('unpause - records data and event', async () => {
      let tx = await pool.unpause({from: admin});
      expectEvent(tx, 'Unpaused', {
        sender: admin,
      });
      Helper.assertEqual(false, await pool.isPaused());

      // duplicated action, but still allowed
      tx = await pool.unpause({from: admin});
      expectEvent(tx, 'Unpaused', {
        sender: admin,
      });
      Helper.assertEqual(false, await pool.isPaused());
    });
  });

  describe('#withdraw funds', async () => {
    beforeEach('deploy contract', async () => {
      pool = await Pool.new(admin, strategies);
    });

    it('revert - when paused', async () => {
      await pool.addOperator(accounts[1], {from: admin});
      await pool.pause({from: accounts[1]});
      await expectRevert(
        pool.withdrawFunds([ethAddress], [new BN(10)], admin, {from: strategies[0]}),
        'only when not paused'
      );
      await pool.unpause({from: admin});
      await pool.removeOperator(accounts[1], {from: admin});
    });

    it('revert - only authorized strategy', async () => {
      await pool.unpause({from: admin});
      await pool.unauthorizeStrategies(strategies, {from: admin});
      await expectRevert(
        pool.withdrawFunds([ethAddress], [new BN(10)], admin, {from: strategies[0]}),
        'not authorized'
      );
      await pool.authorizeStrategies(strategies, {from: admin});
    });

    it('revert - invalid lengths for tokens and amounts', async () => {
      await expectRevert(pool.withdrawFunds([ethAddress], [], admin, {from: strategies[0]}), 'invalid lengths');
      await expectRevert(
        pool.withdrawFunds([ethAddress], [new BN(1), new BN(2)], admin, {from: strategies[0]}),
        'invalid lengths'
      );
    });

    it('revert - transfer eth to none-payable contract', async () => {
      let contract = await NonePayableContract.new();
      await Helper.sendEtherWithPromise(accounts[0], pool.address, new BN(1));
      await expectRevert(
        pool.withdrawFunds([ethAddress], [new BN(1)], contract.address, {from: strategies[0]}),
        'transfer eth failed'
      );
    });

    it('revert - balance not enough', async () => {
      let ethBalance = await Helper.getBalancePromise(pool.address);
      await expectRevert(
        pool.withdrawFunds([ethAddress], [ethBalance.add(new BN(1))], admin, {from: strategies[0]}),
        'transfer eth failed'
      );
      let token = await Token.new();
      let tokenAmount = new BN(200);
      await token.transfer(pool.address, tokenAmount);

      await expectRevert.unspecified(
        pool.withdrawFunds([ethAddress], [ethBalance.add(new BN(1))], admin, {from: strategies[0]})
      );
    });

    it('correct balances changed', async () => {
      await Helper.sendEtherWithPromise(accounts[0], pool.address, new BN(20));
      let token = await Token.new();
      let tokenAmount = new BN(200);
      await token.transfer(pool.address, tokenAmount);

      let recipient = accounts[5];
      let ethBalRecipientBefore = await Helper.getBalancePromise(recipient);
      let tokenBalRecipientBefore = await token.balanceOf(recipient);
      let ethBalPoolBefore = await Helper.getBalancePromise(pool.address);
      let tokenBalPoolBefore = await token.balanceOf(pool.address);

      let ethAmount = await Helper.getBalancePromise(pool.address);
      ethAmount = ethAmount.div(new BN(2));
      tokenAmount = await token.balanceOf(pool.address);
      tokenAmount = tokenAmount.div(new BN(3));

      let tx = await pool.withdrawFunds([ethAddress, token.address], [ethAmount, tokenAmount], recipient, {
        from: strategies[0],
      });

      Helper.assertEqual(ethBalRecipientBefore.add(ethAmount), await Helper.getBalancePromise(recipient));
      Helper.assertEqual(tokenBalRecipientBefore.add(tokenAmount), await token.balanceOf(recipient));
      Helper.assertEqual(ethBalPoolBefore.sub(ethAmount), await Helper.getBalancePromise(pool.address));
      Helper.assertEqual(tokenBalPoolBefore.sub(tokenAmount), await token.balanceOf(pool.address));
      let id = 0;
      for (let i = 0; i < tx.receipt.logs.length; i++) {
        if (tx.receipt.logs[i].event == 'WithdrawToken') {
          if (id == 0) {
            // withdraw eth event
            id++;
            Helper.assertEqual(ethAddress, tx.receipt.logs[i].args.token);
            Helper.assertEqual(strategies[0], tx.receipt.logs[i].args.sender);
            Helper.assertEqual(recipient, tx.receipt.logs[i].args.recipient);
            Helper.assertEqual(ethAmount, tx.receipt.logs[i].args.amount);
          } else {
            // withdraw token event
            Helper.assertEqual(token.address, tx.receipt.logs[i].args.token);
            Helper.assertEqual(strategies[0], tx.receipt.logs[i].args.sender);
            Helper.assertEqual(recipient, tx.receipt.logs[i].args.recipient);
            Helper.assertEqual(tokenAmount, tx.receipt.logs[i].args.amount);
          }
        }
      }
    });
  });
});
