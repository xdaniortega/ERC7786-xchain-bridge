// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {InputBox} from "../InputBox.sol";
import {QuorumAttestator} from "../QuorumAttestator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title InputBoxFactory
 * @notice Factory contract for deploying InputBox instances with their associated QuorumAttestator
 * @dev This factory ensures proper initialization of InputBox with a QuorumAttestator
 */
contract InputBoxFactory is Ownable {
    event InputBoxDeployed(
        address indexed inputBox,
        address indexed quorumAttestator,
        address indexed owner
    );

    error ZeroAddress();
    error InvalidAttestors();

    /**
     * @notice Deploys a new InputBox instance with its associated QuorumAttestator
     * @param initialAttestors Array of addresses that will be the initial attestors
     * @param owner Address that will own the InputBox and QuorumAttestator
     * @return inputBox Address of the deployed InputBox
     * @return quorumAttestator Address of the deployed QuorumAttestator
     */
    function deployInputBox(
        address[] calldata initialAttestors,
        address owner,
        address attestationContract
    ) external returns (address inputBox, address quorumAttestator) {
        if (initialAttestors.length == 0) revert InvalidAttestors();

        // Deploy InputBox and register the QuorumAttestator
        inputBox = address(
            new InputBox(owner)
        );

        inputBox.setQuorumAttestator(attestationContract);

        emit InputBoxDeployed(inputBox, quorumAttestator, owner);
    }
}
