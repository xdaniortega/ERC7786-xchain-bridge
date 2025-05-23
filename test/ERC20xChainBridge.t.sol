// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20xChainBridge} from "../contracts/ERC20xChainBridge.sol";
import {InputBox} from "../contracts/inputBox.sol";
import {QuorumAttestator} from "../contracts/quorumAttestator.sol";
import {ERC20Mock} from "../contracts/mocks/ERC20Mock.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "forge-std/Test.sol";

contract ERC20xChainBridgeTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    ERC20xChainBridge erc20xChainBridge;
    ERC20xChainBridge mock_erc20xChainBridge;
    InputBox inputBox;
    QuorumAttestator quorumAttestator;
    ERC20Mock erc20Mock;

    address admin = vm.addr(1);
    address user1 = vm.addr(2);
    address attestator1 = vm.addr(3);
    address attestator2 = vm.addr(4);
    address attestator3 = vm.addr(5);
    address user2 = vm.addr(6);
    address[] initialAttestors = [admin, attestator1, attestator2, attestator3];

    uint256 USER_INITIAL_BALANCE = 1000;

    function setUp() public {
        vm.startPrank(admin);
        erc20Mock = new ERC20Mock("Test", "TEST");
        erc20Mock.mint(user1, USER_INITIAL_BALANCE);
        vm.deal(address(user1), 1 ether);

        quorumAttestator = new QuorumAttestator(initialAttestors, admin);
        inputBox = new InputBox(address(quorumAttestator), admin);
        erc20xChainBridge = new ERC20xChainBridge(address(inputBox));
        mock_erc20xChainBridge = new ERC20xChainBridge(address(inputBox));
        inputBox.registerBridge(address(mock_erc20xChainBridge));// This step is bc we cannot deterministically deploy in same network twice
        vm.stopPrank();
    }

    function test_transferCrossChain() public {
        assertEq(erc20Mock.balanceOf(user1), USER_INITIAL_BALANCE);
        assertEq(erc20Mock.balanceOf(user2), 0);

        vm.startPrank(user1);
        erc20Mock.approve(address(erc20xChainBridge), 100);
        bytes32 messageId = erc20xChainBridge.transferCrossChain{value: 0.1 ether}(address(erc20Mock), address(mock_erc20xChainBridge), address(user2), 100);
        vm.stopPrank();

        vm.startPrank(attestator1);
        bytes32 messageHashToVerify = messageId.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(3, messageHashToVerify);
        bytes memory signature1 = abi.encodePacked(r, s, v);
        quorumAttestator.attestMessage(messageId, signature1);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert(InputBox.NotEnoughSignatures.selector);
        inputBox.executeMessage(messageId);
        vm.stopPrank();

        vm.startPrank(attestator2);
        messageHashToVerify = messageId.toEthSignedMessageHash();
        (v, r, s) = vm.sign(4, messageHashToVerify);
        bytes memory signature2 = abi.encodePacked(r, s, v);
        quorumAttestator.attestMessage(messageId, signature2);
        vm.stopPrank();

        vm.startPrank(admin);
        inputBox.executeMessage(messageId);
        vm.stopPrank();
    }
}