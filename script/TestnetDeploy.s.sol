// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Contract as UNAIToken} from "../src/UNAI.sol";
import {Contract as UNAITokenV1} from "../test/UNAIV1Mock.sol";
import {UNAIMigration} from "../src/UNAIMigration.sol";

contract TestnetDeploy is Script {
    UNAITokenV1 public unaiV1;
    UNAIToken public unaiV2;
    UNAIMigration public migration;

    uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_PRIVATE_KEY"));
    address constant DEX_ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008; // Sepolia

    function run() public {
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy V1 Token
        // unaiV1 = new UNAITokenV1(payable(deployer), DEX_ROUTER);
        // console.log("UNAI V1 deployed at:", address(unaiV1));

        // Deploy V2 Token
        unaiV2 = new UNAIToken(payable(deployer), DEX_ROUTER);
        console.log("UNAI V2 deployed at:", address(unaiV2));

        // Deploy Migration Contract
        // migration = new UNAIMigration(, address(unaiV2));
        migration = new UNAIMigration(0x96666d6bdD2CC52ef5f6A379D13f8F59866b9F90, address(unaiV2));
        console.log("Migration contract deployed at:", address(migration));

        // Fund migration contract with V2 tokens
        uint256 totalSupply = unaiV2.totalSupply();
        unaiV2.transfer(address(migration), totalSupply);
        console.log("Transferred %s V2 tokens to migration contract", totalSupply);

        vm.stopBroadcast();
    }
}
