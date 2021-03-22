const {expectRevert} = require('@openzeppelin/test-helpers');
const {smockit} = require('@eth-optimism/smock');
const expectEvent = require('@openzeppelin/test-helpers/src/expectEvent');
const {assert} = require('chai');
const {BigNumber} = require('ethers');
const {ethers} = require('hardhat');

const Helper = require('./helper');
const {ethAddress, zeroAddress} = require('./helper.js');
const KNC = '0xdd974d5c2e2928dea5f71b9825b8b646686bd200';
const LINK = '0x514910771af9ca656af840dff83e8264ecf986ca';
const PRECISION = BigNumber.from(10).pow(18);

let ChainLinkPriceOracle;
let MockChainLinkAggregatorProxy;
let admin;
let operator;
let oracle;
let tokens = [];
let quoteEthProxies = [];
let quoteUsdProxies = [];
let chainlinkKNCETH;
let chainlinkKNCUSD;
let chainlinkLINKETH;
let chainlinkLINKUSD;
let chainlinkKNCETHData = {
  decimals: BigNumber.from('18'),
  roundId: BigNumber.from('55340232221128656907'),
  answer: BigNumber.from('1513236447719294'),
  startedAt: BigNumber.from('1616373514'),
  updatedAt: BigNumber.from('1616373664'),
  answeredInRound: BigNumber.from('55340232221128656907'),
};
let chainlinkKNCUSDData = {
  decimals: BigNumber.from('8'),
  roundId: BigNumber.from('55340232221128655889'),
  answer: BigNumber.from('274000000'),
  startedAt: BigNumber.from('1616392877'),
  updatedAt: BigNumber.from('1616392877'),
  answeredInRound: BigNumber.from('55340232221128655889'),
};
let chainlinkLINKETHData = {
  decimals: BigNumber.from('18'),
  roundId: BigNumber.from('73786976294838206534'),
  answer: BigNumber.from('16231590000000000'),
  startedAt: BigNumber.from('1616389750'),
  updatedAt: BigNumber.from('1616389750'),
  answeredInRound: BigNumber.from('73786976294838206534'),
};
let chainlinkLINKUSDData = {
  decimals: BigNumber.from('8'),
  roundId: BigNumber.from('73786976294838206621'),
  answer: BigNumber.from('2910735691'),
  startedAt: BigNumber.from('1616383279'),
  updatedAt: BigNumber.from('1616383279'),
  answeredInRound: BigNumber.from('73786976294838206621'),
};

contract('ChainLinkPriceOracle', (accounts) => {
  before('Global setup', async () => {
    ChainLinkPriceOracle = await ethers.getContractFactory('ChainLinkPriceOracle');
    MockChainLinkAggregatorProxy = await ethers.getContractFactory('MockChainLinkAggregatorProxy');

    ChainlinkKNCETH = await MockChainLinkAggregatorProxy.deploy();
    ChainlinkKNCUSD = await MockChainLinkAggregatorProxy.deploy();
    ChainlinkLINKETH = await MockChainLinkAggregatorProxy.deploy();
    ChainlinkLINKUSD = await MockChainLinkAggregatorProxy.deploy();
    chainlinkKNCETH = await smockit(ChainlinkKNCETH);
    chainlinkKNCUSD = await smockit(ChainlinkKNCUSD);
    chainlinkLINKETH = await smockit(ChainlinkLINKETH);
    chainlinkLINKUSD = await smockit(ChainlinkLINKUSD);

    chainlinkKNCETH.smocked.decimals.will.return.with(chainlinkKNCETHData.decimals);
    chainlinkKNCETH.smocked.latestRoundData.will.return.with([
      chainlinkKNCETHData.roundId,
      chainlinkKNCETHData.answer,
      chainlinkKNCETHData.startedAt,
      chainlinkKNCETHData.updatedAt,
      chainlinkKNCETHData.answeredInRound,
    ]);

    chainlinkKNCUSD.smocked.decimals.will.return.with(chainlinkKNCUSDData.decimals);
    chainlinkKNCUSD.smocked.latestRoundData.will.return.with([
      chainlinkKNCUSDData.roundId,
      chainlinkKNCUSDData.answer,
      chainlinkKNCUSDData.startedAt,
      chainlinkKNCUSDData.updatedAt,
      chainlinkKNCUSDData.answeredInRound,
    ]);

    chainlinkLINKETH.smocked.decimals.will.return.with(chainlinkLINKETHData.decimals);
    chainlinkLINKETH.smocked.latestRoundData.will.return.with([
      chainlinkLINKETHData.roundId,
      chainlinkLINKETHData.answer,
      chainlinkLINKETHData.startedAt,
      chainlinkLINKETHData.updatedAt,
      chainlinkLINKETHData.answeredInRound,
    ]);

    chainlinkLINKUSD.smocked.decimals.will.return.with(chainlinkLINKUSDData.decimals);
    chainlinkLINKUSD.smocked.latestRoundData.will.return.with([
      chainlinkLINKUSDData.roundId,
      chainlinkLINKUSDData.answer,
      chainlinkLINKUSDData.startedAt,
      chainlinkLINKUSDData.updatedAt,
      chainlinkLINKUSDData.answeredInRound,
    ]);

    tokens = [KNC, LINK];
    quoteEthProxies = [chainlinkKNCETH.address, chainlinkLINKETH.address];
    quoteUsdProxies = [chainlinkKNCUSD.address, chainlinkLINKUSD.address];

    [admin, operator] = await ethers.getSigners();
  });

  describe('#constructor', async () => {
    it('invalid params', async () => {
      await expectRevert(ChainLinkPriceOracle.deploy(zeroAddress), 'admin 0');
    });

    it('correct data inited', async () => {
      oracle = await ChainLinkPriceOracle.deploy(admin.address);
      Helper.assertEqual(admin.address, await oracle.admin());
    });
  });

  describe('#update aggregator proxy data', async () => {
    beforeEach('init data', async () => {
      oracle = await ChainLinkPriceOracle.deploy(admin.address);
    });

    it('reverts not admin', async () => {
      await expectRevert(
        oracle.connect(operator).updateAggregatorProxyData(tokens, quoteEthProxies, quoteUsdProxies),
        'only admin'
      );
    });

    it('reverts invalid length data', async () => {
      tmpQuoteEthProxies = [ChainlinkKNCETH.address];
      await expectRevert(
        oracle.updateAggregatorProxyData(tokens, tmpQuoteEthProxies, quoteUsdProxies),
        'invalid length data'
      );

      tmpQuoteUsdProxies = [ChainlinkKNCUSD.address];
      await expectRevert(
        oracle.updateAggregatorProxyData(tokens, quoteEthProxies, tmpQuoteUsdProxies),
        'invalid length data'
      );
    });

    it('updates aggregator proxy data', async () => {
      await oracle.updateAggregatorProxyData(tokens, quoteEthProxies, quoteUsdProxies);
    });
  });

  describe('#conversion rate', async () => {
    beforeEach('init data', async () => {
      oracle = await ChainLinkPriceOracle.deploy(admin.address);
      oracle.updateAggregatorProxyData(tokens, quoteEthProxies, quoteUsdProxies);
    });

    it('get conversion rate for KNC->ETH', async () => {
      const conversionRate = await oracle.conversionRate(
        KNC,
        ethAddress,
        0 // amount not needed for chainlink
      );
      Helper.assertEqual(conversionRate.toString(), chainlinkKNCETHData.answer.toString());
    });

    it('get conversion rate for ETH->KNC', async () => {
      const conversionRate = await oracle.conversionRate(
        ethAddress,
        KNC,
        0 // amount not needed for chainlink
      );
      Helper.assertEqual(
        conversionRate.toString(),
        PRECISION.mul(PRECISION).div(chainlinkKNCETHData.answer).toString()
      );
    });

    it('get conversion rate for LINK->ETH', async () => {
      const conversionRate = await oracle.conversionRate(
        LINK,
        ethAddress,
        0 // amount not needed for chainlink
      );
      Helper.assertEqual(conversionRate.toString(), chainlinkLINKETHData.answer.toString());
    });

    it('get conversion rate for ETH->LINK', async () => {
      const conversionRate = await oracle.conversionRate(
        ethAddress,
        LINK,
        0 // amount not needed for chainlink
      );
      Helper.assertEqual(
        conversionRate.toString(),
        PRECISION.mul(PRECISION).div(chainlinkLINKETHData.answer).toString()
      );
    });

    it('get conversion rate for KNC->LINK', async () => {
      let srcRate;
      let destRate;
      let rateQuoteEth;
      let rateQuoteUsd;

      const conversionRate = await oracle.conversionRate(
        KNC,
        LINK,
        0 // amount not needed for chainlink
      );

      srcRate =
        chainlinkKNCETHData.decimals < 18
          ? chainlinkKNCETHData.answer.mul(10 ** (18 - chainlinkKNCETHData.decimals))
          : chainlinkKNCETHData.answer.div(10 ** (chainlinkKNCETHData.decimals - 18));
      destRate =
        chainlinkLINKETHData.decimals < 18
          ? chainlinkLINKETHData.answer.mul(10 ** (18 - chainlinkLINKETHData.decimals))
          : chainlinkLINKETHData.answer.div(10 ** (chainlinkLINKETHData.decimals - 18));
      rateQuoteEth = PRECISION.mul(srcRate).div(destRate);

      srcRate =
        chainlinkKNCUSDData.decimals < 18
          ? chainlinkKNCUSDData.answer.mul(10 ** (18 - chainlinkKNCUSDData.decimals))
          : chainlinkKNCUSDData.answer.div(10 ** (chainlinkKNCUSDData.decimals - 18));
      destRate =
        chainlinkLINKUSDData.decimals < 18
          ? chainlinkLINKUSDData.answer.mul(10 ** (18 - chainlinkLINKUSDData.decimals))
          : chainlinkLINKUSDData.answer.div(10 ** (chainlinkLINKUSDData.decimals - 18));
      rateQuoteUsd = PRECISION.mul(srcRate).div(destRate);

      Helper.assertEqual(conversionRate.toString(), rateQuoteEth.add(rateQuoteUsd).div(2).toString());
    });

    it('get conversion rate for LINK->KNC', async () => {
      let srcRate;
      let destRate;
      let rateQuoteEth;
      let rateQuoteUsd;

      const conversionRate = await oracle.conversionRate(
        LINK,
        KNC,
        0 // amount not needed for chainlink
      );

      srcRate =
        chainlinkLINKETHData.decimals < 18
          ? chainlinkLINKETHData.answer.mul(10 ** (18 - chainlinkLINKETHData.decimals))
          : chainlinkLINKETHData.answer.div(10 ** (chainlinkLINKETHData.decimals - 18));
      destRate =
        chainlinkKNCETHData.decimals < 18
          ? chainlinkKNCETHData.answer.mul(10 ** (18 - chainlinkKNCETHData.decimals))
          : chainlinkKNCETHData.answer.div(10 ** (chainlinkKNCETHData.decimals - 18));
      rateQuoteEth = PRECISION.mul(srcRate).div(destRate);

      srcRate =
        chainlinkLINKUSDData.decimals < 18
          ? chainlinkLINKUSDData.answer.mul(10 ** (18 - chainlinkLINKUSDData.decimals))
          : chainlinkLINKUSDData.answer.div(10 ** (chainlinkLINKUSDData.decimals - 18));
      destRate =
        chainlinkKNCUSDData.decimals < 18
          ? chainlinkKNCUSDData.answer.mul(10 ** (18 - chainlinkKNCUSDData.decimals))
          : chainlinkKNCUSDData.answer.div(10 ** (chainlinkKNCUSDData.decimals - 18));
      rateQuoteUsd = PRECISION.mul(srcRate).div(destRate);

      Helper.assertEqual(conversionRate.toString(), rateQuoteEth.add(rateQuoteUsd).div(2).toString());
    });
  });

  describe('#token aggregator proxy data', async () => {
    beforeEach('init data', async () => {
      oracle = await ChainLinkPriceOracle.deploy(admin.address);
      oracle.updateAggregatorProxyData(tokens, quoteEthProxies, quoteUsdProxies);
    });

    it('get token aggregator proxy addresses', async () => {
      const proxiesKNC = await oracle.getTokenAggregatorProxyData(KNC);
      const proxiesLINK = await oracle.getTokenAggregatorProxyData(LINK);

      Helper.assertEqual(proxiesKNC['quoteEthProxy'], chainlinkKNCETH.address);
      Helper.assertEqual(proxiesKNC['quoteUsdProxy'], chainlinkKNCUSD.address);
      Helper.assertEqual(proxiesLINK['quoteEthProxy'], chainlinkLINKETH.address);
      Helper.assertEqual(proxiesLINK['quoteUsdProxy'], chainlinkLINKUSD.address);
    });
  });

  describe('#get rate', async () => {
    beforeEach('init data', async () => {
      oracle = await ChainLinkPriceOracle.deploy(admin.address);
      oracle.updateAggregatorProxyData(tokens, quoteEthProxies, quoteUsdProxies);
    });

    it('get rate over eth', async () => {
      let rate;

      rate = await oracle.getRateOverEth(KNC);
      Helper.assertEqual(rate.toString(), chainlinkKNCETHData.answer.toString());

      rate = await oracle.getRateOverEth(LINK);
      Helper.assertEqual(rate.toString(), chainlinkLINKETHData.answer.toString());
    });

    it('get 0 rate over eth', async () => {
      let rate;

      chainlinkKNCETH.smocked.latestRoundData.will.return.with([
        chainlinkKNCETHData.roundId,
        BigNumber.from('-1'),
        chainlinkKNCETHData.startedAt,
        chainlinkKNCETHData.updatedAt,
        chainlinkKNCETHData.answeredInRound,
      ]);
      chainlinkLINKETH.smocked.latestRoundData.will.return.with([
        chainlinkLINKETHData.roundId,
        BigNumber.from('-1'),
        chainlinkLINKETHData.startedAt,
        chainlinkLINKETHData.updatedAt,
        chainlinkLINKETHData.answeredInRound,
      ]);

      rate = await oracle.getRateOverEth(KNC);
      Helper.assertEqual(rate.toString(), '0');

      rate = await oracle.getRateOverEth(LINK);
      Helper.assertEqual(rate.toString(), '0');
    });

    it('get rate over usd', async () => {
      let rate;

      rate = await oracle.getRateOverUsd(KNC);
      Helper.assertEqual(rate.toString(), chainlinkKNCUSDData.answer.mul(10 ** 10).toString());

      rate = await oracle.getRateOverUsd(LINK);
      Helper.assertEqual(rate.toString(), chainlinkLINKUSDData.answer.mul(10 ** 10).toString());
    });

    it('get 0 rate over usd', async () => {
      let rate;

      chainlinkKNCUSD.smocked.latestRoundData.will.return.with([
        chainlinkKNCUSDData.roundId,
        BigNumber.from('-1'),
        chainlinkKNCUSDData.startedAt,
        chainlinkKNCUSDData.updatedAt,
        chainlinkKNCUSDData.answeredInRound,
      ]);
      chainlinkLINKUSD.smocked.latestRoundData.will.return.with([
        chainlinkLINKUSDData.roundId,
        BigNumber.from('-1'),
        chainlinkLINKUSDData.startedAt,
        chainlinkLINKUSDData.updatedAt,
        chainlinkLINKUSDData.answeredInRound,
      ]);

      rate = await oracle.getRateOverUsd(KNC);
      Helper.assertEqual(rate.toString(), '0');

      rate = await oracle.getRateOverUsd(LINK);
      Helper.assertEqual(rate.toString(), '0');
    });
  });
});
