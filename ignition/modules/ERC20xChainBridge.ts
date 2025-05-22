import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Run this script by running `npx hardhat ignition --module ERC20xChainBridge`

// An ERC20xChainBridge is a contract that allows users to transfer ERC20 tokens between chains.
// It needs an inputBox to be deployed first and a quorumAttestator.
export default buildModule("ERC20xChainBridge", (m) => {
  // Get the first 3 accounts as signers
  const initialSigners = [
    m.getAccount(0), // owner
    m.getAccount(1), // attestator1
    m.getAccount(2), // attestator2
    m.getAccount(3), // attestator3
  ]

  const quorumAttestator = m.contract("QuorumAttestator", [initialSigners, 2, initialSigners[0]]);
  const inputBox = m.contract("InputBox", [quorumAttestator, initialSigners[0]]);
  const erc20xChainBridge = m.contract("ERC20xChainBridge", [inputBox]);

  return { erc20xChainBridge };
}); 