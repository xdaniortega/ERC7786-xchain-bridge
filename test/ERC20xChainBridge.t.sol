// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20xChainBridge} from "../contracts/ERC20xChainBridge.sol";
import {InputBox} from "../contracts/inputBox.sol";
import {QuorumAttestator} from "../contracts/quorumAttestator.sol";
import {ERC20Mock} from "../contracts/mocks/ERC20Mock.sol";
import "forge-std/Test.sol";

contract ERC20xChainBridgeTest is Test {
    ERC20xChainBridge erc20xChainBridge;
    InputBox inputBox;
    QuorumAttestator quorumAttestator;
    ERC20Mock erc20Mock;

    address admin = vm.addr(0);
    address attestator1 = vm.addr(1);
    address attestator2 = vm.addr(2);
    address attestator3 = vm.addr(3);

    function setUp() public {
        vm.startPrank(admin);
        erc20Mock = new ERC20Mock("Test", "TEST", 18);
        quorumAttestator = new QuorumAttestator([admin, attestator1, attestator2, attestator3], 2, admin);
        inputBox = new InputBox(address(quorumAttestator), admin);
        erc20xChainBridge = new ERC20xChainBridge(address(inputBox));
        vm.stopPrank();
    }

    function test_transferCrossChain() public {
        erc20Mock.approve(address(erc20xChainBridge), 100);
        vm.startPrank(admin);
        erc20xChainBridge.transferCrossChain(address(erc20Mock), 1, address(0), 100);
        vm.stopPrank();
    }
}