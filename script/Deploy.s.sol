// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Contract as UNAIToken} from "../src/UNAI.sol";

contract Deploy is Script {
    UNAIToken public unaiToken;

    uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_PRIVATE_KEY"));

    address payable UNAI_TOKEN_ADDRESS = payable(vm.envAddress("UNAI_TOKEN_ADDRESS"));

    // Set dex router for the network being deploying to
    address constant DEX_ROUTER = address(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008);
    // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D //mainnet
    // 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008 //sepolia

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // Deploy UNAI token contract
        unaiToken = UNAIToken(UNAI_TOKEN_ADDRESS);

        vm.stopBroadcast();
    }
}
