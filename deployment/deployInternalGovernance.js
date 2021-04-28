require('@nomiclabs/hardhat-ethers');

let gasPrice;

async function verifyContract(hre, contractAddress, ctorArgs) {
  await hre.run('verify:verify', {
    address: contractAddress,
    constructorArguments: ctorArgs,
  });
}

const operators = [
  "0xbe2f0354d970265bfc36d383af77f72736b81b54", // Mike
  "0xf214dDE57f32F3F34492Ba3148641693058D4A9e", // Victor
  "0xdE6BBD964b9D0148d46FE6e2E9Cf72B020ADc519", // Sunny
  "0xf3d872b9e8d314820dc8e99dafbe1a3feedc27d5", // Spyros
  "0x417446168952735b8f51dF840a1838AE78104558", // Shane
  "0x5565d64f29Ea17355106DF3bA5903Eb793B3e139", // Loi
]

const admin = "0x3eb01b3391ea15ce752d01cf3d3f09dec596f650";

const rewardRecipient = "0x43ec6ecffc1e9faab5627341c2186b08d4acdfc2";
const governance = "0x7Ec8FcC26bE7e9E85B57E73083E5Fe0550d8A7fE";
const rewardDistributor = "0x5EC0DcF4f6F55f28550c70B854082993fdc0D3B2";

task('deployInternalGov', 'deploy internal governance for Kyber').setAction(
  async (taskArgs, hre) => {
    const BN = ethers.BigNumber;
    const [deployer] = await ethers.getSigners();
    deployerAddress = await deployer.getAddress();
    console.log(`Deployer address: ${deployerAddress}`)

    // contract deployment
     gasPrice = new BN.from(32).mul(new BN.from(10).pow(new BN.from(18)));
    const KyberInternalGovernance = await ethers.getContractFactory('KyberInternalGovernance');
    for(let i = 0; i < operators.length; i++) {
      console.log(`Deploying for operator: ${operators[i]}`)
      let contract = await KyberInternalGovernance.deploy(
        admin, rewardRecipient, governance, rewardDistributor, operators[i],
      {
        gasPrice: gasPrice
      });
      await contract.deployed();
      console.log(`Internal governance for ${operators[i]} address: ${contract.address}`);
      console.log('Verifying contracts...');
      // verify addresses
      await verifyContract(hre, contract.address, [admin, rewardRecipient, governance, rewardDistributor, operators[i]]);
    }
    console.log('setup completed');
    process.exit(0);
  }
);
