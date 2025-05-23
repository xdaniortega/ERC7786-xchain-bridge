// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC7786GatewaySource, IERC7786Receiver} from "./interfaces/IERC7786.sol";
import {IInputBox} from "./interfaces/IInputbox.sol";
import {CAIP2} from "@openzeppelin/contracts/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC20Mintable} from './interfaces/IERC20Mintable.sol';
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract ERC20xChainBridge is IERC7786Receiver, IERC7786GatewaySource, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
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

    constructor(address _inputBox) {
        inputBox = _inputBox;
    }

    function transferCrossChain(address token, uint256 chainId, address to, uint256 amount) public payable nonReentrant returns (bytes32) {
        IERC20(token).safeTransferFrom(msg.sender, to, amount);

        bytes32 mid = _prepareAndSendMessage(token, chainId, to, amount);
        
        _storeTransfer(mid, token, to, amount, chainId);

        return mid;
    }

    function _prepareAndSendMessage(
        address token,
        uint256 chainId,
        address to,
        uint256 amount
    ) internal returns (bytes32) {
        uint256 impact = _calculateImpact(token, amount);
        bytes memory payload = _createPayload(token, amount, to);
        bytes[] memory attributes = _createAttributes(impact);
        
        uint256 nonce = IInputBox(inputBox).getNonce();
        bytes memory payloadInputBox = abi.encode(nonce++, msg.sender, payload);

        string memory destinationChain = CAIP2.format("eip155", Strings.toString(chainId));
        string memory receiver = CAIP10.format("eip155", Strings.toHexString(uint256(uint160(to))));
        
        return _sendMessage(destinationChain, receiver, payloadInputBox, attributes);
    }

    function _calculateImpact(address token, uint256 amount) internal view returns (uint256) {
        //here for example we could measure the impact on liquidity of the token or smthng, for now 
        // we will just see how much % of the supply is being transferred
        uint256 supply = IERC20(token).totalSupply();
        uint256 impact = (amount * 100) / supply;
        // This will be the number of signatures required to execute the message
        if(impact > 0 ) return 2;
        else{
            return 1;
        }
    }

    function _createPayload(address token, uint256 amount, address to) internal pure returns (bytes memory) {
        bytes4 operationSelector = IERC20Mintable.mint.selector;
        return abi.encode(operationSelector, token, amount, to);
    }

    function _createAttributes(uint256 impact) internal pure returns (bytes[] memory) {
        bytes[] memory attributes = new bytes[](1);
        attributes[0] = abi.encode(impact);
        return attributes;
    }

    function _storeTransfer(
        bytes32 mid,
        address token,
        address to,
        uint256 amount,
        uint256 chainId
    ) internal {
        crossChainTransfers[mid] = CrossChainTransfer({
            token: token,
            to: to,
            amount: amount,
            chainId: chainId,
            refundAddress: payable(msg.sender),
            state: STATE.PENDING
        });
                //todo:callback handler to burn the tokens

    }

    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(
        string memory destinationChain, // CAIP-2 chain identifier
        string memory receiver, // CAIP-10 account address (does not include the chain identifier)
        bytes memory payload,
        bytes[] memory attributes
    ) public payable returns (bytes32 mid) {
        return _sendMessage(destinationChain, receiver, payload, attributes);
    }

    function executeMessage(        string calldata messageId, // gateway specific, empty or unique
        string calldata sourceChain, // CAIP-2 chain identifier
        string calldata sender, // CAIP-10 account address (does not include the chain identifier)
        bytes calldata payload,
        bytes[] calldata attributes) public payable returns (bytes4) {
        //todo: implement
    }
        function supportsAttribute(bytes4 selector) external view returns (bool){
            //todo: implement
        }


    /// INTERNAL FUNCTIONS
    function _sendMessage(
        string memory destinationChain,
        string memory receiver,
        bytes memory payload,
        bytes[] memory attributes
    ) internal returns (bytes32 _mid) {
        if(msg.value < BASE_FEE) revert NotEnoughFunds();

        // On a potential production implementation, I'd introduce a DA solution where inputBox would fetch this arguments from
        // and proposeMessage would only be called with the messageId
        _mid = IInputBox(inputBox).proposeMessage(destinationChain, receiver, payload, attributes);

        emit MessagePosted(
            _mid,
            CAIP10.local(msg.sender),
            CAIP10.format(destinationChain, receiver),
            payload,
            attributes
        );    
    }

    /// GETTERS
    function getInputBox() public view returns (address) {
        return inputBox;
    }
}