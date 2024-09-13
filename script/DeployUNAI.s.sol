// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Contract as UNAIToken} from "../src/UNAI.sol";

contract Deploy is Script {
    UNAIToken public unaiToken;

    uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_PRIVATE_KEY"));

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // Deploy UNAI token contract
        unaiToken = new UNAIToken();
        console.log("UNAI Token deployed at:", address(unaiToken));

        vm.stopBroadcast();
    }
}
