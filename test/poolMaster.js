const hre = require('hardhat');
let setupComplete = false;

let poolMaster;
let signer;

contract('Pool', function () {
  if (process.env.ALCHEMY_KEY) {
    before(`turn on mainnet forking and impersonate account`, async () => {
      try {
        await network.provider.request({
          method: 'hardhat_reset',
          params: [
            {
              forking: {
                jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
                blockNumber: 11095000,
              },
            },
          ],
        });
        // impersonate deployer account
        await network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: ['0xDd102CeDa27a2283dC85028f9bF7d022d8a640d2'],
        });
        signer = await ethers.provider.getSigner('0xDd102CeDa27a2283dC85028f9bF7d022d8a640d2');
        setupComplete = true;
      } catch (e) {
        console.log(e);
        setupComplete = false;
      }
    });

    beforeEach('deploy pool master contract', async () => {
      if (setupComplete) {
        let PoolMaster = await ethers.getContractFactory('PoolMaster');
        let knc = await ethers.getContractAt('ERC20', '0xdeFA4e8a7bcBA345F687a2f1456F5Edd9CE97202');
        console.log(await knc.totalSupply());
        poolMaster = await PoolMaster.deploy(
          'Pool KNC',
          'PKNC',
          '0x9AAb3f75489902f3a48495025729a0AF77d4b11e', // kyberProxy
          '0xeadb96F1623176144EBa2B24e35325220972b3bD', // kyberStaking
          '0x7Ec8FcC26bE7e9E85B57E73083E5Fe0550d8A7fE', // kyberGovernance
          '0x5EC0DcF4f6F55f28550c70B854082993fdc0D3B2', // rewardDistributor
          // note: using knc impl, not proxy, because of mainnet fork limitation
          // tested with remix to deploy, no tx revert
          '0xdeFA4e8a7bcBA345F687a2f1456F5Edd9CE97202',
          5 // admin fee
        );
      }
    });

    it('runs setup and see if setupComplete', async () => {
      console.log(`Setup complete: ${setupComplete}`);
    });

    if (setupComplete) {
      it('should log admin address', async () => {
        let adminAddress = await poolMaster.admin();
        console.log(adminAddress);
      });
    }
    after('disable mainnet fork', async () => {
      await network.provider.request({
        method: 'hardhat_reset',
        params: [],
      });
    });
  }
});
