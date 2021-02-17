# KyberDao Katana

## Architecture

![governance-v2-architecture](./gov-v2-architecture.jpg)

### AaveGovernanceV2
- voting delay (time between a proposal is submitted and the voting is opened): 0 blocks, as for us this process is done beforehand in the governance forum
- guardian: Aave Guardian multisig
- executors whitelisted: Executor (short) and Executor (long)
- owner (entity able to change the strategy, voting delay and authorize/unauthorize executors): Executor 2, the long timelock 

### Executor (short)
It will control the whole Aave protocol v1, the token distributor used in v1, the contract collecting the fees of v1, the Reserve Ecosystem of AAVE and any change in this timelock itself
- admin (the only address enable to interact with this executor): Aave Governance v2
- delay (time between a proposals passes and its actions get executed): 1 day
- grace period (time after the delay during which the proposal can be executed): 5 days
- proposition threshold: 0.5%
- voting duration: 3 days
- vote differential: 0.5%
- quorum: 2%

### Executor (long)
It will control the upgradeability of the AAVE token, the stkAAVE, any change in the parameters of the Governance v2 and any change in the parameters of this timelock itself
- admin: Aave Governance v2
- delay: 7 days
- grace period: 5 days
- proposition threshold: 2%
- voting duration: 10 days
- vote differential: 15%
- quorum: 20%

### Governance strategy (the contract determining how the voting/proposition powers are calculated)
- Based on AAVE+stkAAVE
- Voting and proposition power are: balanceOfAAVE + delegationReceivedOfAAVE + balanceOfstkAAVE + delegationReceivedOfstkAAVE (with delegation being voting or proposition depending on the case)
- Total voting and proposition supply: AAVE supply


## Setup
1. Clone this repo
2. `yarn install`

## Compilation
`yarn compile` to compile contracts for all solidity versions.

## Contract Deployment / Interactions

For interactions or contract deployments on public testnets / mainnet, create a `.env` file specifying your private key and infura api key, with the following format:

```
PRIVATE_KEY=0x****************************************************************
INFURA_API_KEY=********************************
```

## Testing with Hardhat
1. If contracts have not been compiled, run `yarn compile`. This step can be skipped subsequently.
2. Run `yarn test`
3. Use `./tst.sh -f` for running a specific test file.

### Example Commands
- `yarn test` (Runs all tests)
- `./tst.sh -f ./test/kyberDao.js` (Test only kyberDao.js)

### Example
`yarn hardhat test --no-compile ./test/kyberDao.js`

## Coverage
`yarn coverage` (Runs coverage for all applicable files)
