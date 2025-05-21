// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC7786GatewaySource, IERC7786Receiver} from "./interfaces/IERC7786.sol";

contract xChainPortal is IERC7786Receiver, IERC7786GatewaySource {
    using SafeERC20 for IERC20;


}