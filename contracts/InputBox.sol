// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IInputBox} from "./interfaces/IInputbox.sol";
import {IQuorumAttestator} from "./interfaces/IQuorumAttestator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract InputBox is IInputBox, Ownable {
    error InvalidQuorumAttestator();
    error InvalidNonce();
    event QuorumAttestatorUpdated(address indexed newQuorumAttestator);

    struct MessageData {
        string destinationChain;
        string receiver;
        bytes payload;
        bytes[] attributes;
        uint256 nonce;
        uint256 blockTimestamp; // This can be used to revert if the message is not signed in specific max wait time
    }

    mapping(bytes32 => MessageData) public messageStore;
    mapping(bytes32 => bool) public isExecuted;

    address public quorumAttestator;
    uint256 public nonce;

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
        //Here we could only allow trusted sources for example
        (uint256 _nonce, address _sender, bytes memory _payload) = abi.decode(_payload, (uint256, address, bytes));
        if (_nonce != nonce++) revert InvalidNonce();
        messageId = computeMessageId(_destinationChain, _receiver, _payload, _attributes, _nonce);
        if (isExecuted[messageId]) revert MessageAlreadyExecuted();

        if (messageExists(messageId)) {
            return messageId;
        }

        messageStore[messageId] = MessageData({
            destinationChain: _destinationChain,
            receiver: _receiver,
            payload: _payload,
            attributes: _attributes,
            blockTimestamp: block.timestamp,
            nonce: _nonce
        });

        emit MessageProposed(messageId, _destinationChain, _receiver);
        return messageId;
    }

    function executeMessage(bytes32 _messageId, bytes[] memory _signatures) public {
        if (!messageExists(_messageId)) revert MessageNotFound();
        if (isExecuted[_messageId]) revert MessageAlreadyExecuted();

        MessageData memory message = messageStore[_messageId];
        // Decode message attributes and check if the number of signatures is enough
        uint256 thresholdSignatures = abi.decode(message.attributes[0], (uint256));
        if(IQuorumAttestator(quorumAttestator).getAttestationsReached(_messageId) < thresholdSignatures) revert NotEnoughSignatures();

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
        nonce++;
        // call execute function of the target contract
        
        emit MessageExecuted(_messageId, _destinationChain, _receiver);
    }

    function getMessageData(bytes32 _messageId) public view returns (MessageData memory) {
        if (!messageExists(_messageId)) revert MessageNotFound();
        return messageStore[_messageId];
    }

    function getNonce() public view returns (uint256) {
        return nonce;
    }

    function computeMessageId(
        string memory _destinationChain,
        string memory _receiver,
        bytes memory _payload,
        bytes[] memory _attributes,
        uint256 _nonce  
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(_destinationChain, _receiver, _payload, _attributes, _nonce));
    }

    function messageExists(bytes32 _messageId) public view returns (bool) {
        return messageStore[_messageId].blockTimestamp != 0;
    }
}