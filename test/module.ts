import chai from 'chai';
import { solidity } from 'ethereum-waffle';
import { ethers } from 'hardhat';

chai.use(solidity);
const { expect } = chai;

describe('AuctionHouse', () => {
  let snapshotId: number;

  before(async () => {
    // deploy
  });

  beforeEach(async () => {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await ethers.provider.send('evm_revert', [snapshotId]);
  });
});
