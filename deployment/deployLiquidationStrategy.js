require('@nomiclabs/hardhat-ethers');
const fs = require('fs');
const path = require('path');

let gasPrice;

async function verifyContract(hre, contractAddress, ctorArgs, contract) {
  await hre.run('verify:verify', {
    address: contractAddress,
    constructorArguments: ctorArgs,
    contract: contract
  });
}

let deployerAddress;
let dmmChainLink;
let dmmChainLinkAddr;
let liquidationStrategy;
let liquidationStrategyAddr;
let liquidateWithKyber;
let liquidateWithKyberAddr;
let outputFilename = "liquidation_strategy_output.json";

const zeroAddress = "0x0000000000000000000000000000000000000000";
const daoOperator = "0xe6a7338cba0a1070adfb22c07115299605454713";
const longExecutor = "0x6758a66cd25fef7767a44895041678fc4ae9afd0";
const treasuryPool = "0x0E590bB5F02A0c38888bFFb45DeE050b8fB60Bda";
const rewardPool = "0xD2D0a0557E5B78E29542d440eC968F9253Daa2e2";

const liquidationStartTime = 1629209227;
const liquidationPeriod = 1209600;
const liquidationDuration = 14400;
const chainlinkValidDuration = 86400; // 24 hours
const lpDiffThreshold = 200; // 2%
const defaultPremiumBps = 200;

const btcEthProxy = '0xdeb288F737066589598e9214E782fa5A8eD689e8';
const btcUsdProxy = '0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c';
const ethUsdProxy = '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419';
const kncEthProxy = '0x656c0544eF4C98A6a98491833A89204Abb045d6b';
const kncUsdProxy = '0xf8fF43E991A81e6eC886a3D281A2C6cC19aE70Fc';
const usdtEthProxy = '0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46';
const usdtUsdProxy = '0x3E7d1eAB13ad0104d2750B8863b489D65364e32D';
const daiEthProxy = '0x773616E4d11A78F511299002da57A0a94577F1f4';
const daiUsdProxy = '0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9';
const usdcEthProxy = '0x986b5E1e1755e3C2440e960477f25201B0a8bbD4';
const usdcUsdProxy = '0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6';

const wethAddress = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const kncAddress = '0xdeFA4e8a7bcBA345F687a2f1456F5Edd9CE97202';
const wbtcAddress = '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599';
const usdtAddress = '0xdac17f958d2ee523a2206206994597c13d831ec7';
const usdcAddress = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';
const daiAddress = '0x6b175474e89094c44da98b954eedeac495271d0f';

const kyberProxyAddress = '0x9AAb3f75489902f3a48495025729a0AF77d4b11e';

// 1. Deploy dmm chainlink price oracle
//  1.1. Add operator to dmm chainlink price oracle
//  1.2. Add default premium bps
//  1.3. Add chainlink price feeds
// 2. Deploy liquidate fee with kyber, strategy is 0x0
//  2.1 Add operator
//  2.2 Set liquidation strategy after it is deployed (after 3)
// 3. Deploy liquidation strategy
//  3.1 Add operator
// 4. Clean up (revoke operator, transfer admin)
task('deployLiquidationStrategy', 'deploy liquidation strategy and liquidate with Kyber')
  .addParam('gasprice', 'The gas price (in gwei) for all transactions')
  .setAction(async (taskArgs, hre) => {
    const BN = ethers.BigNumber;
    const [deployer] = await ethers.getSigners();
    deployerAddress = await deployer.getAddress();
    console.log(`Deployer address: ${deployerAddress}`)

    let outputData = {};
    gasPrice = new BN.from(10**9 * taskArgs.gasprice);
    console.log(`Deploy gas price: ${gasPrice.toString(10)} (${taskArgs.gasprice} gweis)`);

    const DmmChainLink = await ethers.getContractFactory('KyberDmmChainLinkPriceOracle');
    if (dmmChainLinkAddr == undefined) {
      dmmChainLink = await DmmChainLink.deploy(
        deployerAddress, wethAddress, [kncAddress], chainlinkValidDuration, lpDiffThreshold,
        { gasPrice: gasPrice }
      );
      await dmmChainLink.deployed();
      dmmChainLinkAddr = dmmChainLink.address;
    } else {
      dmmChainLink = await DmmChainLink.attach(dmmChainLinkAddr);
    }
    console.log(`DmmChainLink address: ${dmmChainLink.address}`);
    outputData["DmmChainLink"] = dmmChainLink.address;

    const LiquidateWithKyber = await ethers.getContractFactory("LiquidateFeeWithKyber");
    if (liquidateWithKyberAddr == undefined) {
      liquidateWithKyber = await LiquidateWithKyber.deploy(
        deployerAddress, wethAddress, zeroAddress, kyberProxyAddress,
        { gasPrice: gasPrice }
      )
    } else {
      liquidateWithKyber = await LiquidateWithKyber.attach(liquidateWithKyberAddr);
    }
    console.log(`LiquidateWithKyber address: ${liquidateWithKyber.address}`)
    outputData["LiquidateWithKyber"] = liquidateWithKyber.address;

    const LiquidationStrategy = await ethers.getContractFactory("LiquidationStrategyBase");
    if (liquidationStrategyAddr == undefined) {
      liquidationStrategy = await LiquidationStrategy.deploy(
        deployerAddress, treasuryPool, rewardPool, liquidationStartTime, liquidationPeriod, liquidationDuration,
        [liquidateWithKyber.address], [dmmChainLink.address],
        { gasPrice: gasPrice }
      )
    } else {
      liquidationStrategy = await LiquidationStrategy.attach(liquidationStrategyAddr);
    }
    console.log(`LiquidationStrategy address: ${liquidationStrategy.address}`)
    outputData["LiquidationStrategy"] = liquidationStrategy.address;

    // setup dmm chainlink price oracle
    console.log(`Adding new operator to dmm chainlink`);
    await dmmChainLink.addOperator(deployerAddress, { gasPrice: gasPrice });

    let chainlinkData = await dmmChainLink.getTokenAggregatorProxyData(kncAddress);
    if (chainlinkData.quoteEthProxy == zeroAddress) {
      console.log(`Updating chainlink price data`);
      await dmmChainLink.updateAggregatorProxyData(
        [kncAddress, wbtcAddress, usdtAddress, usdcAddress, daiAddress],
        [kncEthProxy, btcEthProxy, usdtEthProxy, usdcEthProxy, daiEthProxy],
        [kncUsdProxy, btcUsdProxy, usdtUsdProxy, usdcUsdProxy, daiUsdProxy],
        { gasPrice: gasPrice }
      );
    }

    let defaultPremiumData = await dmmChainLink.getConfig();
    if (defaultPremiumData.liquidateLpBps != defaultPremiumBps) {
      console.log(`Setting default premium data`);
      await dmmChainLink.updateDefaultPremiumData(defaultPremiumBps, defaultPremiumBps, { gasPrice: gasPrice });
    }

    console.log(`Done setting up DmmChainLink`);

    // setup liquidate
    let strategy = await liquidateWithKyber.liquidationStrategy();
    if (strategy != liquidationStrategy.address) {
      console.log(`Set liquidation strategy to liquidator`);
      await liquidateWithKyber.updateContracts(liquidationStrategy.address, kyberProxyAddress, { gasPrice: gasPrice });
    }
    console.log(`Add operator to liquidate with kyber`);
    await liquidateWithKyber.addOperator(daoOperator, { gasPrice: gasPrice });

    console.log(`Done setting up LiquidateWithKyber`);

    // setup liquidation
    console.log(`Add operator to liquidation strategy`);
    await liquidationStrategy.addOperator(daoOperator, { gasPrice: gasPrice });

    console.log(`Done setting up LiquidationStrategy`);

    // // clean up, remove operator from dmm chainlink, transfer admin role in dmm chainlink + liquidation strategy
    // await dmmChainLink.removeOperator(deployerAddress, { gasPrice: gasPrice });
    // await dmmChainLink.transferAdminQuickly(longExecutor, { gasPrice: gasPrice });
    // await liquidationStrategy.transferAdminQuickly(longExecutor, { gasPrice: gasPrice });

    console.log(`Verify DmmChainLink at: ${dmmChainLink.address}`);
    await verifyContract(hre, dmmChainLink.address,
      [deployerAddress, wethAddress, [kncAddress], chainlinkValidDuration, lpDiffThreshold],
      "contracts/treasury/priceOracle/KyberDmmChainLinkPriceOracle.sol:KyberDmmChainLinkPriceOracle"
    );

    console.log(`Verify LiquidateWithKyber at: ${liquidateWithKyber.address}`);
    await verifyContract(hre, liquidateWithKyber.address,
      [deployerAddress, wethAddress, zeroAddress, kyberProxyAddress],
      "contracts/treasury/liquidateWithKyber/LiquidateFeeWithKyber.sol:LiquidateFeeWithKyber"
    );

    console.log(`Verify LiquidationStrategy at: ${liquidationStrategy.address}`);
    await verifyContract(hre, liquidationStrategy.address,
      [deployerAddress, treasuryPool, rewardPool, liquidationStartTime, liquidationPeriod, liquidationDuration, [liquidateWithKyber.address], [dmmChainLink.address]],
      "contracts/treasury/LiquidationStrategyBase.sol:LiquidationStrategyBase"
    );

    exportAddresses(outputData);
    console.log('setup completed');

    process.exit(0);
  }
);

function exportAddresses(dictOutput) {
  let json = JSON.stringify(dictOutput, null, 2);
  fs.writeFileSync(path.join(__dirname, outputFilename), json);
}
