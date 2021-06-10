import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {EthersProviderWrapper} from '@nomiclabs/hardhat-ethers/dist/src/ethers-provider-wrapper';
import type EthersT from 'ethers';
import {BigNumber as BN} from 'ethers';
const {ethers} = require('ethers') as typeof EthersT;
let oneEth = ethers.constants.WeiPerEther;

export async function impersonateAcc(
  network: any,
  ethersProvider: EthersProviderWrapper,
  user: string,
  admin: SignerWithAddress
) {
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
  return ethersProvider.getSigner(user);
}

export async function mineNewBlockAt(network: any, timestamp: BN) {
  await network.provider.request({
    method: 'evm_mine',
    params: [timestamp],
  });
}
