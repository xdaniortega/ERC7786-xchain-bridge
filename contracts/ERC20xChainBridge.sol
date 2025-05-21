// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC7786GatewaySource, IERC7786Receiver} from "./interfaces/IERC7786.sol";
import {IInputBox} from "./interfaces/IInputbox.sol";
import {CAIP2} from "@openzeppelin/contracts/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ERC721xChainBridge is IERC7786Receiver, IERC7786GatewaySource, ReentrancyGuard {
    using SafeERC20 for IERC20;

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
        address payable refundAddress;
        STATE state;
    }

    /// @notice Mock base for a crosschain transfer, this would be fetched from an oracle or a trusted source
    uint256 immutable baseFee = 0.1 ether;
    address public inputBox;
    mapping(bytes32 => CrossChainTransfer) public crossChainTransfers; // mid => crossChainTransfer

    constructor(address inputBox) {
        inputBox = inputBox;
    }

    function transferCrossChain(address token, address to, uint256 amount, uint256 chainId) public payable nonReentrant returns (bytes32 mid) {
        bytes memory message = abi.encode(token, to, amount);

        IERC20(token).safeTransferFrom(msg.sender, to, amount);

        //here encode logic of transfering into the payload

        //here for example we could measure the impact on liquidity of the token or smthng, for now 
        // we will just see how much % of the supply is being transferred
        uint256 supply = IERC20(token).totalSupply();
        uint256 impact = (amount * 100) / supply;

        // encode destinationchain with CAIP2
        string memory destinationChain = CAIP2.format(chainId);
        string memory receiver = CAIP10.format(chainId, to);
        // payload will be erc20 mint operation, amount and destination address
        bytes4 operationSelector = IERC20.mint.selector;
        bytes memory payload = abi.encode(operationSelector, token, amount, to);

        //todo: check attributes
        bytes[] memory attributes = new bytes[](1);
        attributes[0] = abi.encode(impact);

        // inside payload I will encode the mint operation, the tokenId and the refundAddress
        // as attributes the number of attestations required
        bytes32 mid = sendMessage(destinationChain, receiver, payload, attributes);
        crossChainTransfers[mid] = CrossChainTransfer({
            token: token,
            to: to,
            amount: amount,
            chainId: chainId,
            refundAddress: payable(msg.sender),
            state: STATE.PENDING
        });

        return mid;

    }

    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(
        string calldata destinationChain, // CAIP-2 chain identifier
        string calldata receiver, // CAIP-10 account address (does not include the chain identifier)
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 mid) {
        if(msg.value < baseFee) revert NotEnoughFunds(msg.value, baseFee);

        // On a potential production implementation, I'd introduce a DA solution where inputBox would fetch this arguments from
        // and proposeMessage would only be called with the messageId
        bytes32 mid = IInputBox(inputBox).proposeMessage(destinationChain, receiver, payload, attributes);

        emit MessagePosted(
            mid,
            CAIP10.format(CAIP2.local(), sender),
            CAIP10.format(destinationChain, receiver),
            payload,
            attributes
        );

        return mid;
    }

    // Also here the receiver/execute logic should be implemented

    /// GETTERS
    function getInputBox() public view returns (address) {
        return inputBox;
    }
}