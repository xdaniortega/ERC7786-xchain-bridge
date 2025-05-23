// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IInputBox} from "./interfaces/IInputbox.sol";
import {IQuorumAttestator} from "./interfaces/IQuorumAttestator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC7786GatewaySource, IERC7786Receiver} from "./interfaces/IERC7786.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import "forge-std/console.sol";

/**
 * @title InputBox
 * @notice A contract that manages cross-chain message proposals and executions
 * @dev Implements a message queue system with quorum-based attestation for cross-chain message validation
 *      Uses a threshold-based signature system to ensure message validity
 *      Supports message nonce tracking and execution state management
 */
contract InputBox is IInputBox, Ownable {
    error InvalidQuorumAttestator();
    error InvalidNonce();
    error NotEnoughSignatures();

    event QuorumAttestatorUpdated(address indexed newQuorumAttestator);

    struct MessageData {
        string destinationChain;
        string receiver;
        bytes payload;
        bytes[] attributes;
        uint256 nonce;
        uint256 blockTimestamp; // This can be used to revert if the message is not signed in specific max wait time
        uint256 thresholdSignatures;
    }

    mapping(bytes32 => MessageData) public messageStore;
    mapping(bytes32 => bool) public isExecuted;
    mapping(string => address) public caip2ToBridge; // CAIP-2 => bridge address

    address public quorumAttestator;
    uint256 public nonce;

    constructor(address _quorumAttestator, address initialOwner) Ownable(initialOwner) {
        if (_quorumAttestator == address(0)) revert InvalidQuorumAttestator();
        quorumAttestator = _quorumAttestator;
        emit QuorumAttestatorUpdated(_quorumAttestator);
    }

    /**
     * @notice Proposes a new cross-chain message for execution
     * @dev Validates the message nonce and creates a new message entry
     * @param _destinationChain The CAIP-2 chain identifier of the destination chain
     * @param _receiver The CAIP-10 account address on the destination chain
     * @param _payload The message payload to be executed
     * @param _attributes Additional attributes for message execution
     * @return messageId The unique identifier for the proposed message
     * @custom:error InvalidNonce Thrown if the message nonce is invalid
     * @custom:error MessageAlreadyExecuted Thrown if the message has already been executed
     */
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

        uint256 thresholdSignatures = IQuorumAttestator(quorumAttestator).assignThresholdSignatures(_attributes);

        messageStore[messageId] = MessageData({
            destinationChain: _destinationChain,
            receiver: _receiver,
            payload: _payload,
            attributes: _attributes,
            blockTimestamp: block.timestamp,
            thresholdSignatures: thresholdSignatures,
            nonce: _nonce
        });

        emit MessageProposed(messageId, _destinationChain, _receiver);
        return messageId;
    }

    /**
     * @notice Executes a proposed cross-chain message
     * @dev Validates message existence and required signatures before execution
     * @param _messageId The unique identifier of the message to execute
     * @custom:error MessageNotFound Thrown if the message does not exist
     * @custom:error MessageAlreadyExecuted Thrown if the message has already been executed
     * @custom:error NotEnoughSignatures Thrown if the required number of signatures is not met
     */
    function executeMessage(bytes32 _messageId) public {
        if (!messageExists(_messageId)) revert MessageNotFound();
        if (isExecuted[_messageId]) revert MessageAlreadyExecuted();

        MessageData memory message = messageStore[_messageId];
        // Decode message attributes and check if the number of signatures is enough
        if(IQuorumAttestator(quorumAttestator).getAttestationsReached(_messageId) < message.thresholdSignatures) revert NotEnoughSignatures();

        _performMessageExecution(
            _messageId,
            message.destinationChain,
            message.receiver,
            message.payload,
            message.attributes
        );
    }

    /**
     * @notice Retrieves the data for a specific message
     * @param _messageId The unique identifier of the message
     * @return The MessageData structure containing all message details
     * @custom:error MessageNotFound Thrown if the message does not exist
     */
    function getMessageData(bytes32 _messageId) public view returns (MessageData memory) {
        if (!messageExists(_messageId)) revert MessageNotFound();
        return messageStore[_messageId];
    }

    /**
     * @notice Returns the current nonce value
     * @return The current nonce value
     */
    function getNonce() public view returns (uint256) {
        return nonce;
    }

    /**
     * @notice Updates the quorum attestator contract address
     * @dev Only callable by the contract owner
     * @param _newQuorumAttestator The address of the new quorum attestator contract
     * @custom:error InvalidQuorumAttestator Thrown if the new quorum attestator address is zero
     */
    function setQuorumAttestator(address _newQuorumAttestator) public onlyOwner {
        if (_newQuorumAttestator == address(0)) revert InvalidQuorumAttestator();
        quorumAttestator = _newQuorumAttestator;
        emit QuorumAttestatorUpdated(_newQuorumAttestator);
    }

    /**
     * @notice Computes a unique message ID based on message parameters
     * @param _destinationChain The CAIP-2 chain identifier
     * @param _receiver The CAIP-10 account address
     * @param _payload The message payload
     * @param _attributes Additional message attributes
     * @param _nonce The message nonce
     * @return The computed message ID
     */
    function computeMessageId(
        string memory _destinationChain,
        string memory _receiver,
        bytes memory _payload,
        bytes[] memory _attributes,
        uint256 _nonce  
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(_destinationChain, _receiver, _payload, _attributes, _nonce));
    }

    /**
     * @notice Checks if a message exists in the store
     * @param _messageId The unique identifier of the message
     * @return True if the message exists, false otherwise
     */
    function messageExists(bytes32 _messageId) public view returns (bool) {
        return messageStore[_messageId].blockTimestamp != 0;
    }

    /**
     * @notice Registers a bridge contract for a specific chain
     * @dev Only callable by the contract owner
     * @param bridge The address of the bridge contract to register
     */
    function registerBridge(address bridge) public onlyOwner {
        caip2ToBridge["hello"] = bridge;
    }

    /**
     * @notice Internal function to execute a validated message
     * @dev Handles the actual execution of the message by calling the destination bridge
     * @param _messageId The unique identifier of the message
     * @param _destinationChain The CAIP-2 chain identifier
     * @param _receiver The CAIP-10 account address
     * @param _payload The message payload
     * @param _attributes Additional message attributes
     */
    function _performMessageExecution(
        bytes32 _messageId,
        string memory _destinationChain,
        string memory _receiver,
        bytes memory _payload,
        bytes[] memory _attributes
    ) internal virtual {
        nonce++;
        // call execute function of the target contract
        // Read and decode destination chain and call executeMessage of the target contract
        //string to address
        address destinationBridge = caip2ToBridge["hello"];

        // Compute a unique message ID
        string memory messageIdString = Strings.toHexString(uint256(_messageId));
        (bool success, bytes memory returnData) = address(destinationBridge).call(
            abi.encodeWithSelector(IERC7786Receiver.executeMessage.selector, messageIdString, _destinationChain, _receiver, _payload, _attributes)
        );
        
        if (!success) {
            // If the call failed, revert with the error data
            if (returnData.length > 0) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            }
            revert("Bridge call failed");
        }

        // If we get here, the call was successful
        isExecuted[_messageId] = true;
        emit MessageExecuted(_messageId, _destinationChain, _receiver);
    }
}