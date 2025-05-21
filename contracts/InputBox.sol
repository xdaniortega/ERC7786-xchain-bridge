// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IInputbox.sol";

contract InputBox is IInputBox, Ownable {
    struct MessageData {
        string destinationChain;
        string receiver;
        bytes payload;
        bytes[] attributes;
    }

    mapping(bytes32 => MessageData) public messageStore;
    mapping(bytes32 => bool) public isExecuted;

    address public quorumAttestator;

    constructor(address _quorumAttestator, address initialOwner) Ownable(initialOwner) {
        if (_quorumAttestator == address(0)) revert InvalidQuorumAttestator();
        quorumAttestator = _quorumAttestator;
        emit QuorumAttestatorUpdated(_quorumAttestator);
    }

    function setQuorumAttestator(address _newQuorumAttestator) public onlyOwner {
        if (_newQuorumAttestator == address(0)) revert InvalidQuorumAttestator();
        quorumAttestator = _newQuorumAttestator;
        emit QuorumAttestatorUpdated(_newQuorumAttestator);
    }

    function proposeMessage(
        string calldata _destinationChain,
        string memory _receiver,
        bytes memory _payload,
        bytes[] memory _attributes
    ) public returns (bytes32 messageId) {
        messageId = keccak256(abi.encode(
            _destinationChain,
            _receiver,
            _payload,
            _attributes
        ));

        if (isExecuted[messageId]) revert MessageAlreadyExecuted();

        if (messageStore[messageId].blockTimestamp != 0) {
            return messageId;
        }

        messageStore[messageId] = MessageData({
            destinationChain: _destinationChain,
            receiver: _receiver,
            payload: _payload,
            attributes: _attributes,
        });

        emit MessageProposed(messageId, msg.sender, _destinationChain, _receiver);
        return messageId;
    }

    function executeMessage(bytes32 _messageId) public {
        if (messageStore[_messageId].blockTimestamp == 0) revert MessageNotFound();
        if (isExecuted[_messageId]) revert MessageAlreadyExecuted();

        if (!IQuorumAttestator(quorumAttestator).isConsensusReached(_messageId)) {
            revert ConsensusNotReached();
        }

        isExecuted[_messageId] = true;

        MessageData memory message = messageStore[_messageId];

        _performMessageExecution(
            _messageId,
            message.destinationChain,
            message.receiver,
            message.payload,
            message.attributes
        );
    }

    function _performMessageExecution(
        bytes32 _messageId,
        string memory _destinationChain,
        string memory _receiver,
        bytes memory _payload,
        bytes[] memory _attributes
    ) internal virtual {
        // call execute function of the target contract
        emit MessageExecuted(_messageId, _destinationChain, _receiver);
    }

    function getMessageData(bytes32 _messageId) public view returns (MessageData memory) {
        if (messageStore[_messageId].blockTimestamp == 0) revert MessageNotFound();
        return messageStore[_messageId];
    }
}