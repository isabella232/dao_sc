const {expectEvent, expectRevert} = require('@openzeppelin/test-helpers');
const BN = web3.utils.BN;

const LiquidationStrategy = artifacts.require('LiquidationStrategy.sol');
const Token = artifacts.require('KyberNetworkTokenV2.sol');
const NonePayableContract = artifacts.require('NonePayableContract.sol');

const Helper = require('./helper.js');
const {zeroAddress, ethAddress, ProposalState} = require('./helper.js');

let admin;
let operators;
let pool;
let strategies;

contract('LiquidationStrategy', function (accounts) {
  before('Global setup', async () => {
    admin = accounts[1];
    operators = [accounts[2], accounts[3]];
    strategies = [accounts[4], accounts[5]];
    pool = await Pool.new(admin, strategies);
  });
});
