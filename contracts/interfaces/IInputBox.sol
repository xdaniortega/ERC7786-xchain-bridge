// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IInputBox {
    event MessageProposed(
        bytes32 indexed messageId,
        string destinationChain,
        string receiver
    );
    event MessageExecuted(
        bytes32 indexed messageId,
        string destinationChain,
        string receiver
    );

    error MessageNotFound();
    error MessageAlreadyExecuted();
    error ConsensusNotReached();
    error InvalidAttestationManager();
    error ExecutionFailed();

    function setQuorumAttestator(address _newManagerAddress) external;
    function proposeMessage(
        string calldata _destinationChain,
        string memory _receiver,
        bytes memory _payload,
        bytes[] memory _attributes
    ) external returns (bytes32 messageId);
    function executeMessage(bytes32 _messageId) external;
    function getNonce() external view returns (uint256);
}
