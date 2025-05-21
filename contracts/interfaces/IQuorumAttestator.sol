// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IQuorumAttestator {
    function isConsensusReached(bytes32 _messageId) external view returns (bool);
}