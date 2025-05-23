// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC7786GatewaySource, IERC7786Receiver } from "./interfaces/IERC7786.sol";
import { IInputBox } from "./interfaces/IInputbox.sol";
import { CAIP2 } from "@openzeppelin/contracts/utils/CAIP2.sol";
import { CAIP10 } from "@openzeppelin/contracts/utils/CAIP10.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Mintable } from "./interfaces/IERC20Mintable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { AttributeLib } from "./libraries/AttributeLib.sol";

import "forge-std/console.sol";
/**
 * @title CrosschainProxy
 * @notice A cross-chain proxy contract that enables communication between different chains
 * @dev Implements the ERC-7786 standard for cross-chain messaging and token transfers
 *      Uses a quorum-based attestation system for message validation
 *      Supports impact-based message execution requirements
 */
contract CrosschainProxy is IERC7786Receiver, IERC7786GatewaySource, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using AttributeLib for bytes[];

    error NotEnoughFunds();

    enum STATE {
        PENDING,
        EXECUTED,
        REJECTED
    }

    struct CrossChainTransfer {
        address token;
        address to;
        uint256 amount;
        uint256 chainId;
        address refundAddress;
        STATE state;
    }

    /// @notice Mock base for a crosschain transfer, this would be fetched from an oracle or a trusted source
    uint256 constant BASE_FEE = 0.1 ether;
    address public inputBox;
    mapping(bytes32 => CrossChainTransfer) public crossChainTransfers; // messageId => crossChainTransfer
    mapping(string => bytes32) public messageIdToMid;

    constructor(address _inputBoxFactory, address attestationContract) Ownable(msg.sender) {
        if (_inputBoxFactory == address(0) || attestationContract == address(0)) revert ZeroAddress();
        
        inputBoxFactory = InputBoxFactory(_inputBoxFactory);
        inputBox = inputBoxFactory.deployInputBox(msg.sender, attestationContract);
    }

    /**
     * @notice Sends a cross-chain message to a destination chain
     * @dev Implements IERC7786GatewaySource.sendMessage
     * @param destinationChain The CAIP-2 chain identifier of the destination chain
     * @param receiver The CAIP-10 account address on the destination chain
     * @param payload The message payload to be executed on the destination chain
     * @param attributes Additional attributes for message execution (e.g., impact level)
     * @return mid The message ID of the sent message
     */
    function sendMessage(
        string memory destinationChain, // CAIP-2 chain identifier (CAIP10 for testing)
        string memory receiver, // CAIP-10 account address (does not include the chain identifier)
        bytes memory payload,
        bytes[] memory attributes
    ) public payable returns (bytes32 mid) {
        return _sendMessage(destinationChain, receiver, payload, attributes);
    }

    /**
     * @notice Executes a received cross-chain message
     * @dev Implements IERC7786Receiver.executeMessage
     * @dev Updates the state of the cross-chain transfer and executes the token minting
     * @param messageId The unique identifier of the message
     * @param sourceChain The CAIP-2 chain identifier of the source chain
     * @param sender The CAIP-10 account address of the sender
     * @param payload The message payload containing the transfer details
     * @param attributes Additional attributes for message execution
     * @return The function selector of executeMessage
     */
    function executeMessage(
        string calldata messageId, // gateway specific, empty or unique
        string calldata sourceChain, // CAIP-2 chain identifier
        string calldata sender, // CAIP-10 account address (does not include the chain identifier)
        bytes calldata payload,
        bytes[] calldata attributes
    ) public payable returns (bytes4) {
        return this.executeMessage.selector;
    }

    /**
     * @notice Checks if the contract supports a specific attribute
     * @param selector The attribute selector to check
     * @return bool True if the attribute is supported, false otherwise
     */
    function supportsAttribute(bytes4 selector) external pure returns (bool) {
        return selector == AttributeLib.IMPACT_KEY;
    }

    /**
     * @notice Returns the address of the InputBox contract
     * @return The address of the InputBox contract
     */
    function getInputBox() public view returns (address) {
        return inputBox;
    }

    /// INTERNAL FUNCTIONS
    // MESSAGE FORWARDING METHODS ------------------------------------------------------------
    /**
     * @notice Prepares and sends a cross-chain message for token transfer
     * @dev Internal function that handles message preparation and sending
     * @param token The address of the token to transfer
     * @param chainId The destination chain identifier
     * @param to The recipient address on the destination chain
     * @param amount The amount of tokens to transfer
     * @return The message ID of the prepared message
     */
    function _prepareAndSendMessage(
        address token,
        address chainId,
        address to,
        uint256 amount
    ) internal returns (bytes32) {
        console.log("amount", amount);
        string memory impact = _calculateImpact(token, amount);
        console.log("impact", impact);
        bytes memory payload = _createPayload(token, amount, to);
        bytes[] memory attributes = _assignImpactAttribute(impact);
        uint256 nonce = IInputBox(inputBox).getNonce();
        bytes memory payloadInputBox = abi.encode(nonce++, msg.sender, payload);

        string memory destinationChain = CAIP2.format("eip155", Strings.toString(1));
        string memory receiver = CAIP10.format("eip155", Strings.toHexString(uint256(uint160(to))));

        return _sendMessage(destinationChain, receiver, payloadInputBox, attributes);
    }

    /**
     * @notice Sends a cross-chain message through the InputBox
     * @dev Internal function that handles the actual message sending
     * @param destinationChain The destination chain identifier
     * @param receiver The receiver address on the destination chain
     * @param payload The message payload
     * @param attributes Additional message attributes
     * @return mid The message ID of the sent message
     */
    function _sendMessage(
        string memory destinationChain,
        string memory receiver,
        bytes memory payload,
        bytes[] memory attributes
    ) internal returns (bytes32 mid) {
        if (msg.value < BASE_FEE) revert NotEnoughFunds();
        // On a potential production implementation, I'd introduce a DA solution where inputBox would fetch this arguments from
        // and proposeMessage would only be called with the messageId
        mid = IInputBox(inputBox).proposeMessage(destinationChain, receiver, payload, attributes);

        emit MessagePosted(
            mid,
            CAIP10.local(msg.sender),
            CAIP10.format(destinationChain, receiver),
            payload,
            attributes
        );
    }

    // IMPACT CALCULATION METHODS ------------------------------------------------------------
    /**
     * @notice Stores the cross-chain transfer details
     * @dev Internal function that records the transfer state
     * @param mid The message ID
     * @param token The token address
     * @param to The recipient address
     * @param amount The transfer amount
     * @param chainId The destination chain ID
     */
    function _storeTransfer(bytes32 mid, address token, address to, uint256 amount, uint256 chainId) internal {
        crossChainTransfers[mid] = CrossChainTransfer({
            token: token,
            to: to,
            amount: amount,
            chainId: chainId,
            refundAddress: payable(msg.sender),
            state: STATE.PENDING
        });
        //todo:callback handler to burn the tokens
        // and to update the state of the transfer to EXECUTED
    }
}
