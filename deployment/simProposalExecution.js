require('@nomiclabs/hardhat-ethers');
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
const chainIdToAddresses = {
  1: {
    kyberGov: '0x7ec8fcc26be7e9e85b57e73083e5fe0550d8a7fe',
    daoOperator: '0xe6a7338cba0a1070adfb22c07115299605454713',
  },
  3: {
    kyberGov: '0xef5a1404E312078cd16B7139a2257eD3bb42F787',
    daoOperator: '0xDdF05698718bA8ed1c9abA198d38a825A64D69e2',
  },
  31337: {
    kyberGov: '0x7ec8fcc26be7e9e85b57e73083e5fe0550d8a7fe',
    daoOperator: '0xe6a7338cba0a1070adfb22c07115299605454713',
  }
};

let oneEth;

let startTimestamp;
let endTimestamp;
let proposalId;

task('simProposalExecution', 'simulate execution of existing proposal')
  .addParam('id', 'Proposal ID')
  .setAction(async (taskArgs) => {
    getForkParams();
    proposalId = taskArgs.id;

    // attempt mainnet forking
    try {
      await network.provider.request({
        method: 'hardhat_reset',
        params: [forkParams],
      });

      oneEth = ethers.constants.WeiPerEther;
      [admin] = await ethers.getSigners();
      getAddresses(await admin.getChainId());
      kyberGov = await ethers.getContractAt('KyberGovernance', kyberGovAddress);
    } catch (e) {
      console.log(e);
      process.exit(1);
    }

    daoOperator = await Helper.impersonateAcc(network, ethers.provider, daoOperator, admin);
    console.log('Fetching proposal details...');
    // get proposal timestamps
    await getProposalDetails();

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
    process.exit(0);
  });

function getForkParams() {
  if (process.env.NODE_URL == undefined) {
    console.log(`Missing NODE_URL in .env`);
    process.exit(1);
  }
  forkParams['forking'] = {jsonRpcUrl: process.env.NODE_URL};
  if (process.env.FORK_BLOCK) forkParams['forking']['blockNumber'] = Number(process.env.FORK_BLOCK);
}

function getAddresses(chainId) {
  kyberGovAddress = chainIdToAddresses[chainId]['kyberGov'];
  daoOperator = chainIdToAddresses[chainId]['daoOperator'];
}

async function getProposalDetails() {
  let result = await kyberGov.getProposalById(proposalId);
  executorAddress = result.executor;
  startTimestamp = result.startTime.toNumber();
  endTimestamp = result.endTime.toNumber();
}
