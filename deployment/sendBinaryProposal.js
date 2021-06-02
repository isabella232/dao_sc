require('@nomiclabs/hardhat-ethers');
const inquirer = require('inquirer');
const fs = require('fs');
const path = require('path');
const fetch = require('node-fetch');

const GnosisWalletABI = [
  {
    constant: true,
    inputs: [{name: '', type: 'uint256'}],
    name: 'owners',
    outputs: [{name: '', type: 'address'}],
    payable: false,
    type: 'function',
  },
  {
    constant: false,
    inputs: [{name: 'owner', type: 'address'}],
    name: 'removeOwner',
    outputs: [],
    payable: false,
    type: 'function',
  },
  {
    constant: false,
    inputs: [{name: 'transactionId', type: 'uint256'}],
    name: 'revokeConfirmation',
    outputs: [],
    payable: false,
    type: 'function',
  },
  {
    constant: true,
    inputs: [{name: '', type: 'address'}],
    name: 'isOwner',
    outputs: [{name: '', type: 'bool'}],
    payable: false,
    type: 'function',
  },
  {
    constant: true,
    inputs: [
      {name: '', type: 'uint256'},
      {name: '', type: 'address'},
    ],
    name: 'confirmations',
    outputs: [{name: '', type: 'bool'}],
    payable: false,
    type: 'function',
  },
  {
    constant: true,
    inputs: [
      {name: 'pending', type: 'bool'},
      {name: 'executed', type: 'bool'},
    ],
    name: 'getTransactionCount',
    outputs: [{name: 'count', type: 'uint256'}],
    payable: false,
    type: 'function',
  },
  {
    constant: false,
    inputs: [{name: 'owner', type: 'address'}],
    name: 'addOwner',
    outputs: [],
    payable: false,
    type: 'function',
  },
  {
    constant: true,
    inputs: [{name: 'transactionId', type: 'uint256'}],
    name: 'isConfirmed',
    outputs: [{name: '', type: 'bool'}],
    payable: false,
    type: 'function',
  },
  {
    constant: true,
    inputs: [{name: 'transactionId', type: 'uint256'}],
    name: 'getConfirmationCount',
    outputs: [{name: 'count', type: 'uint256'}],
    payable: false,
    type: 'function',
  },
  {
    constant: true,
    inputs: [{name: '', type: 'uint256'}],
    name: 'transactions',
    outputs: [
      {name: 'destination', type: 'address'},
      {name: 'value', type: 'uint256'},
      {name: 'data', type: 'bytes'},
      {name: 'executed', type: 'bool'},
    ],
    payable: false,
    type: 'function',
  },
  {
    constant: true,
    inputs: [],
    name: 'getOwners',
    outputs: [{name: '', type: 'address[]'}],
    payable: false,
    type: 'function',
  },
  {
    constant: true,
    inputs: [
      {name: 'from', type: 'uint256'},
      {name: 'to', type: 'uint256'},
      {name: 'pending', type: 'bool'},
      {name: 'executed', type: 'bool'},
    ],
    name: 'getTransactionIds',
    outputs: [{name: '_transactionIds', type: 'uint256[]'}],
    payable: false,
    type: 'function',
  },
  {
    constant: true,
    inputs: [{name: 'transactionId', type: 'uint256'}],
    name: 'getConfirmations',
    outputs: [{name: '_confirmations', type: 'address[]'}],
    payable: false,
    type: 'function',
  },
  {
    constant: true,
    inputs: [],
    name: 'transactionCount',
    outputs: [{name: '', type: 'uint256'}],
    payable: false,
    type: 'function',
  },
  {
    constant: false,
    inputs: [{name: '_required', type: 'uint256'}],
    name: 'changeRequirement',
    outputs: [],
    payable: false,
    type: 'function',
  },
  {
    constant: false,
    inputs: [{name: 'transactionId', type: 'uint256'}],
    name: 'confirmTransaction',
    outputs: [],
    payable: false,
    type: 'function',
  },
  {
    constant: false,
    inputs: [
      {name: 'destination', type: 'address'},
      {name: 'value', type: 'uint256'},
      {name: 'data', type: 'bytes'},
    ],
    name: 'submitTransaction',
    outputs: [{name: 'transactionId', type: 'uint256'}],
    payable: false,
    type: 'function',
  },
  {
    constant: true,
    inputs: [],
    name: 'MAX_OWNER_COUNT',
    outputs: [{name: '', type: 'uint256'}],
    payable: false,
    type: 'function',
  },
  {
    constant: true,
    inputs: [],
    name: 'required',
    outputs: [{name: '', type: 'uint256'}],
    payable: false,
    type: 'function',
  },
  {
    constant: false,
    inputs: [
      {name: 'owner', type: 'address'},
      {name: 'newOwner', type: 'address'},
    ],
    name: 'replaceOwner',
    outputs: [],
    payable: false,
    type: 'function',
  },
  {
    constant: false,
    inputs: [{name: 'transactionId', type: 'uint256'}],
    name: 'executeTransaction',
    outputs: [],
    payable: false,
    type: 'function',
  },
  {
    inputs: [
      {name: '_owners', type: 'address[]'},
      {name: '_required', type: 'uint256'},
    ],
    payable: false,
    type: 'constructor',
  },
  {payable: true, type: 'fallback'},
  {
    anonymous: false,
    inputs: [
      {indexed: true, name: 'sender', type: 'address'},
      {indexed: true, name: 'transactionId', type: 'uint256'},
    ],
    name: 'Confirmation',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      {indexed: true, name: 'sender', type: 'address'},
      {indexed: true, name: 'transactionId', type: 'uint256'},
    ],
    name: 'Revocation',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [{indexed: true, name: 'transactionId', type: 'uint256'}],
    name: 'Submission',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [{indexed: true, name: 'transactionId', type: 'uint256'}],
    name: 'Execution',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [{indexed: true, name: 'transactionId', type: 'uint256'}],
    name: 'ExecutionFailure',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      {indexed: true, name: 'sender', type: 'address'},
      {indexed: false, name: 'value', type: 'uint256'},
    ],
    name: 'Deposit',
    type: 'event',
  },
  {anonymous: false, inputs: [{indexed: true, name: 'owner', type: 'address'}], name: 'OwnerAddition', type: 'event'},
  {anonymous: false, inputs: [{indexed: true, name: 'owner', type: 'address'}], name: 'OwnerRemoval', type: 'event'},
  {
    anonymous: false,
    inputs: [{indexed: false, name: 'required', type: 'uint256'}],
    name: 'RequirementChange',
    type: 'event',
  },
];
const ETHERSCAN_KEY = process.env.ETHERSCAN_KEY;
const chainIdToEtherscanURL = {
  1: '',
  3: '-ropsten',
  4: '-rinkeby',
  5: '-goerli',
  42: '-kovan',
};

let chainId;

let kyberGovernance;
let gnosisWallet;

let kyberGovernanceAddress;
let gnosisWalletAddress;
let executorAddress;
let votingPowerStrategyAddress;
let contractsToCall;
let outputFilename;

let startTimestamp;
let endTimestamp;
let link;

async function inquireForContractCalls(ethers) {
  let result = {targets: contractsToCall, weiValues: [], signatures: [], calldatas: [], withDelegatecalls: []};
  for (let contractAddress of contractsToCall) {
    let contract = await instantiateContract(ethers, contractAddress);

    // try to see if there is implementation() function
    // prompt user for implementation contract address
    // due to permissioned controls in reading it directly
    for (let funcName of Object.keys(contract.interface.functions)) {
      if (funcName == 'implementation()') {
        contract = await instantiateContract(ethers, contractAddress, true);
      }
    }

    let functionList = getWriteFunctionsList(contract.interface.functions);
    let functionData = await getFunctionOptionAndData(contract, functionList);
    result.weiValues.push(functionData.weiValue);
    result.signatures.push(functionData.name);
    result.withDelegatecalls.push(functionData.delegateCall);
    let functionName = contract.interface.functions[functionData.name].name;
    functionData = await contract.populateTransaction[functionName](...functionData.inputArgs);
    result.calldatas.push(`0x` + functionData.data.substring(10));
  }
  return result;
}

async function instantiateContract(ethers, address, askImplementation = false) {
  if (askImplementation) {
    let question = [
      {
        type: 'input',
        name: 'address',
        message: `Implementation address of ${address} for function list`,
      },
    ];
    address = (await inquirer.prompt(question)).address;
  }
  let abi = await pullABIFromEtherscan(address);
  return new ethers.Contract(address, abi);
}

async function pullABIFromEtherscan(address) {
  if (ETHERSCAN_KEY == undefined) {
    console.log('Require etherscan key, exiting...');
    process.exit(0);
  } else {
    let abiRequest = await fetch(
      `https://api${chainIdToEtherscanURL[chainId]}.etherscan.io/api?module=contract&action=getabi` +
        `&address=${address}` +
        `&apikey=${ETHERSCAN_KEY}`
    );
    abi = await abiRequest.json();
    if (abi.status == '0') {
      console.log(abi.result);
      process.exit(0);
    }
    return abi.result;
  }
}

function getWriteFunctionsList(allFunctions) {
  let result = [];
  for ([funcName, funcFrag] of Object.entries(allFunctions)) {
    if (!funcFrag.constant) result.push(funcName);
  }
  return result;
}

async function getFunctionOptionAndData(contract, functionList) {
  let question = [
    {
      type: 'list',
      name: 'functionName',
      message: `Select function for contract ${contract.address}`,
      choices: functionList,
    },
  ];
  let selectedFunction = (await inquirer.prompt(question)).functionName;
  let inputList = contract.interface.functions[selectedFunction].inputs;
  question = inputList.map((paramType) => {
    let inputType = paramType.type.includes('int') ? 'number' : 'input';
    return {type: inputType, name: paramType.name, message: paramType.name};
  });
  let functionInputArgs = await inquirer.prompt(question);
  let functionInputValues = inputList.map((paramType) => {
    return functionInputArgs[paramType.name];
  });
  functionInputValues = convertInputValues(functionInputValues);
  let weiValue = '0';
  // check if payable
  if (contract.interface.functions[selectedFunction].payable) {
    question = [
      {
        type: 'number',
        name: 'weiValue',
        message: `Ether wei value`,
      },
    ];
    weiValue = (await inquirer.prompt(question)).weiValue;
  }
  // check delegatecall
  question = [
    {
      type: 'confirm',
      name: 'delegatecall',
      message: `Use delegate call?`,
    },
  ];
  let delegateCall = (await inquirer.prompt(question)).delegateCall;
  return {
    name: selectedFunction,
    inputArgs: functionInputValues,
    weiValue: weiValue,
    delegateCall: delegateCall,
  };
}

function convertInputValues(inputValues) {
  return inputValues.map((inputValue) => {
    if (typeof inputValue == 'number') {
      let BN = ethers.BigNumber;
      let numDecimals = countDecimals(inputValue);
      if (numDecimals == 0) return new BN.from(inputValue);
      inputValue = inputValue * 10 ** numDecimals;
      inputValue = new BN.from(inputValue)
        .mul(ethers.constants.WeiPerEther)
        .div(new BN.from(10).mul(new BN.from(numDecimals)))
        .toHexString();
      return inputValue;
    }
    // for array, do mapping
    try {
      inputValue = JSON.parse(inputValue);
      return inputValue;
    } catch (e) {
      return inputValue;
    }
  });
}

task('createBinaryProposal', 'create binary proposal')
  .addParam('f', 'JSON file for settings and addresses')
  .addOptionalParam('s', 'Send tx to multisig wallet', false, types.boolean)
  .setAction(async (taskArgs) => {
    const addressPath = path.join(__dirname, taskArgs.f);
    const addressParams = JSON.parse(fs.readFileSync(addressPath, 'utf8'));
    parseValidateInput(addressParams);
    const [sender] = await ethers.getSigners();
    console.log(`Signing txns with ${await sender.getAddress()}`);
    chainId = await sender.getChainId();

    kyberGovernance = await ethers.getContractAt('KyberGovernance', kyberGovernanceAddress);
    gnosisWallet = new ethers.Contract(gnosisWalletAddress, GnosisWalletABI, sender);
    let binaryCallData = await inquireForContractCalls(ethers);

    let txData = (
      await kyberGovernance.populateTransaction.createBinaryProposal(
        executorAddress,
        votingPowerStrategyAddress,
        {
          targets: binaryCallData.targets,
          weiValues: binaryCallData.weiValues,
          signatures: binaryCallData.signatures,
          calldatas: binaryCallData.calldatas,
          withDelegatecalls: binaryCallData.withDelegatecalls,
        },
        startTimestamp,
        endTimestamp,
        link
      )
    ).data;

    addressParams['txData'] = txData;
    let json = JSON.stringify(addressParams, null, 2);
    fs.writeFileSync(path.join(__dirname, outputFilename), json);

    if ((await gnosisWallet.isOwner(sender.address)) && taskArgs.s) {
      console.log(`Sending tx to gnosisWallet ${gnosisWalletAddress}`);
      await gnosisWallet.submitTransaction(kyberGovernanceAddress, 0, txData, {gasLimit: 2000000});
    }
    process.exit(0);
  });

function parseValidateInput(jsonInput) {
  gnosisWalletAddress = jsonInput['gnosisWallet'];
  kyberGovernanceAddress = jsonInput['governance'];
  executorAddress = jsonInput['executor'];
  votingPowerStrategyAddress = jsonInput['votingPowerStrategy'];
  contractsToCall = jsonInput['contractsToCall'];
  startTimestamp = jsonInput['startTimestamp'];
  endTimestamp = jsonInput['endTimestamp'];
  link = jsonInput['link'];
  outputFilename = jsonInput['outputFilename'];

  // check start and timestamps
  let now = Math.floor(new Date().getTime() / 1000);
  if (startTimestamp < now) {
    console.error(`Bad start timestamp, use value > ${now}`);
    process.exit(0);
  } else if (endTimestamp <= startTimestamp) {
    console.error(`Bad start and end timestamps`);
    process.exit(0);
  }
}

function countDecimals(value) {
  if (Math.floor(value) !== value) return value.toString().split('.')[1].length || 0;
  return 0;
}
