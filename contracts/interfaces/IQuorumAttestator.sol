// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IQuorumAttestator {
    function isConsensusReached(bytes32 _messageId) external view returns (bool);
    
    /// @notice Assigns the number of required signatures based on message attributes
    /// @param attributes The array of encoded attributes from the message
    /// @return The number of required signatures (1 for low impact, 2 for high impact)
    function assignThresholdSignatures(bytes[] calldata attributes) external pure returns (uint256);

    /// @notice Gets the number of attestations reached for a given message
    /// @param _messageId The ID of the message to check
    /// @return The number of attestations received for the message
    function getAttestationsReached(bytes32 _messageId) external view returns (uint256);
}