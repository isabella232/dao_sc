require('@nomiclabs/hardhat-ethers');
const path = require('path');
const fs = require('fs');
const Helper = require('../test/testHelpers/hardhat');
let kyberGov;

let forkParams = {};
let admin;
let daoOperator;
let kyberGovAddress;
let executorAddress;
let voterAddresses = [
  '0xf977814e90da44bfa03b6295a0616a897441acec',
  '0x3Be35d6C5FFeAe62CB3f6CB8a23653b6501A060d',
  '0x0bfEc35a1A3550Deed3F6fC76Dde7FC412729a91',
  '0x06890D4c65A4cB75be73D7CCb4a8ee7962819E81',
];

let txData;
let startTimestamp;
let endTimestamp;
let proposalId;

task('simFullProposal', 'simulate proposal creation, voting and execution')
  .addParam('f', 'JSON file for binary proposal data info')
  .setAction(async (taskArgs) => {
    const jsonPath = path.join(__dirname, taskArgs.f);
    const jsonInput = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
    parseInput(jsonInput);

    // attempt mainnet forking
    await network.provider.request({
      method: 'hardhat_reset',
      params: [forkParams],
    });

    [admin] = await ethers.getSigners();
    kyberGov = await ethers.getContractAt('KyberGovernance', kyberGovAddress);

    daoOperator = await Helper.impersonateAcc(network, ethers.provider, daoOperator, admin);

    // send proposal data
    console.log(`Creating proposal...`);
    try {
      let tx = await daoOperator.sendTransaction({
        to: kyberGovAddress,
        gasLimit: 2000000,
        value: 0,
        data: txData,
      });
      await tx.wait();

      proposalId = await kyberGov.getProposalsCount();
    } catch (e) {
      console.log(e);
      process.exit(1);
    }

    // fast forward time
    await Helper.mineNewBlockAt(network, startTimestamp + 1);

    console.log(`Voting for proposal...`);
    for (let i = 0; i < voterAddresses.length; i++) {
      let voter = await Helper.impersonateAcc(network, ethers.provider, voterAddresses[i], admin);
      await kyberGov.connect(voter).submitVote(proposalId, 1);
    }

    console.log(`Queueing proposal...`);
    await Helper.mineNewBlockAt(network, endTimestamp + 1);
    try {
      await kyberGov.connect(admin).queue(proposalId);
    } catch (e) {
      console.log(e);
      process.exit(1);
    }

    console.log(`Execute proposal...`);
    let executor = await ethers.getContractAt('DefaultExecutorWithTimelock', executorAddress);
    let timeDelay = await executor.getDelay();
    await Helper.mineNewBlockAt(network, endTimestamp + timeDelay.toNumber() + 1);
    try {
      await kyberGov.connect(admin).execute(proposalId);
    } catch (e) {
      console.log(e);
      process.exit(1);
    }
    console.log(`All good! =)`);
  });

function parseInput(jsonInput) {
  txData = jsonInput['txData'];
  startTimestamp = jsonInput['startTimestamp'];
  endTimestamp = jsonInput['endTimestamp'];
  kyberGovAddress = jsonInput['governance'];
  executorAddress = jsonInput['executor'];
  daoOperator = jsonInput['gnosisWallet'];
  if (process.env.NODE_URL == undefined) {
    console.log(`Missing NODE_URL in .env`);
    process.exit(1);
  }
  forkParams['forking'] = {jsonRpcUrl: process.env.NODE_URL};
  if (process.env.FORK_BLOCK) forkParams['forking']['blockNumber'] = Number(process.env.FORK_BLOCK);
}
