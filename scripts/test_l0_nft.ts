import { ethers } from "hardhat";
import { TestChainList } from "./testnet.const";

async function main() {
    const selectObj = TestChainList.find(item=>item.name === 'Goerli');

  const L0Factory = await ethers.getContractFactory("ONFT721");
  const l0Fac = await L0Factory.deploy('Picasso-L0', 'PICA', 150000, selectObj?.endpoint as string);

  await l0Fac.deployed();

  console.log(`deployed to ${l0Fac.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
