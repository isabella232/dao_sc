require('@nomiclabs/hardhat-ethers');
const path = require('path');
const fs = require('fs');

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

let ONE;
let oneEth;

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
    try {
      await network.provider.request({
        method: 'hardhat_reset',
        params: [forkParams]
      });

      ONE = ethers.constants.One;
      oneEth = ethers.constants.WeiPerEther;
      [admin] = await ethers.getSigners();
      kyberGov = await ethers.getContractAt('KyberGovernance', kyberGovAddress);
    } catch (e) {
      console.log(e);
      process.exit(1);
    }

    daoOperator = await impersonateAcc(daoOperator);

    // send proposal data
    console.log(`Creating proposal...`);
    try {
      let tx = await daoOperator.sendTransaction({
        to: kyberGovAddress,
        gasLimit: 2000000,
        value: 0,
        data: txData,
      });
      let txResult = await tx.wait();

      await getProposalIdFromTx(txResult);
    } catch (e) {
      console.log(e);
      process.exit(1);
    }

    // fast forward time
    await mineNewBlockAt(startTimestamp + 1);

    console.log(`Voting for proposal...`);
    for (let i = 0; i < voterAddresses.length; i++) {
      let voter = await impersonateAcc(voterAddresses[i]);
      await kyberGov.connect(voter).submitVote(proposalId, 1);
    }

    console.log(`Queueing proposal...`);
    await mineNewBlockAt(endTimestamp + 1);
    try {
      await kyberGov.connect(admin).queue(proposalId);
    } catch (e) {
      console.log(e);
      process.exit(1);
    }

    console.log(`Execute proposal...`);
    let executor = await ethers.getContractAt('DefaultExecutorWithTimelock', executorAddress);
    let timeDelay = await executor.getDelay();
    await mineNewBlockAt(endTimestamp + timeDelay.toNumber() + 1);
    try {
      await kyberGov.connect(admin).execute(proposalId);
    } catch (e) {
      console.log(e);
      process.exit(1);
    }
    console.log(`All good! =)`);
    process.exit(0);
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
  forkParams['forking'] = {'jsonRpcUrl': process.env.NODE_URL}
  if (process.env.FORK_BLOCK) forkParams['forking']['blockNumber'] = Number(process.env.FORK_BLOCK);
}

async function impersonateAcc(user) {
  // fund account
  try {
    await admin.sendTransaction({
      to: user,
      gasLimit: 80000,
      value: oneEth,
    });
  } catch (e) {}

  await network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [user],
  });
  return await ethers.provider.getSigner(user);
}

async function getProposalIdFromTx(txResult) {
  const iface = kyberGov.interface;
  const decodedBinaryEvent = txResult.logs.map((log) => iface.decodeEventLog('BinaryProposalCreated', log.data));
  const decodedGenericEvent = txResult.logs.map((log) => iface.decodeEventLog('GenericProposalCreated', log.data));
  let proposalDetails = decodedBinaryEvent != undefined ? decodedBinaryEvent[0] : decodedGenericEvent[0];
  proposalId = proposalDetails.proposalId;
}

async function mineNewBlockAt(timestamp) {
  await network.provider.request({
    method: 'evm_mine',
    params: [timestamp],
  });
}
