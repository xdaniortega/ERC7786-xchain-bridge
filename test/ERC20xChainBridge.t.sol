// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20xChainBridge} from "../contracts/ERC20xChainBridge.sol";
import {InputBox} from "../contracts/inputBox.sol";
import {QuorumAttestator} from "../contracts/quorumAttestator.sol";
import {ERC20Mock} from "../contracts/mocks/ERC20Mock.sol";
import "forge-std/Test.sol";

contract ERC20xChainBridgeTest is Test {
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

        quorumAttestator = new QuorumAttestator(initialAttestors, admin);
        inputBox = new InputBox(address(quorumAttestator), admin);
        erc20xChainBridge = new ERC20xChainBridge(address(inputBox));
        mock_erc20xChainBridge = new ERC20xChainBridge(address(inputBox));
        vm.stopPrank();
    }

    function test_transferCrossChain() public {
        assertEq(erc20Mock.balanceOf(user1), USER_INITIAL_BALANCE);
        assertEq(erc20Mock.balanceOf(user2), 0);

        vm.startPrank(user1);
        erc20Mock.approve(address(erc20xChainBridge), 100);
        erc20xChainBridge.transferCrossChain(address(erc20Mock), 1, address(erc20xChainBridge), 100);
        vm.stopPrank();
    }
}