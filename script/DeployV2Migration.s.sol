// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UNAI as UNAIV2Token} from "../src/UNAIV2.sol";
import {UNAIMigration} from "../src/UNAIMigration.sol";

contract DeployV2Migration is Script {
    UNAIV2Token public unaiV2Token;
    UNAIMigration public migration;

    uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_PRIVATE_KEY"));
    address UNAI_V1_ADDRESS = vm.envAddress("UNAI_TOKEN_ADDRESS");

    // Set dex router for the network being deploying to
    address constant DEX_ROUTER = address(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008);
    // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D //mainnet
    // 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008 //sepolia

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // Get deployer address
        address deployer = vm.addr(deployerPrivateKey);

        // Deploy UNAI V2 token contract
        // Constructor params: tax collector (deployer), router address
        unaiV2Token = new UNAIV2Token(payable(deployer), DEX_ROUTER);
        console.log("UNAI V2 Token deployed at:", address(unaiV2Token));

        // Deploy Migration contract
        migration = new UNAIMigration(UNAI_V1_ADDRESS, address(unaiV2Token));
        console.log("Migration Contract deployed at:", address(migration));

        // Transfer all V2 tokens to migration contract
        // Note: In V2 contract, deployer receives all initial supply
        uint256 totalSupply = unaiV2Token.totalSupply();
        unaiV2Token.transfer(address(migration), totalSupply);
        console.log("Transferred", totalSupply, "V2 tokens to migration contract");

        // Set migration contract as tax exempt to avoid fees during migration
        unaiV2Token.setTaxExempt(address(migration), true);
        console.log("Set migration contract as tax exempt");

        vm.stopBroadcast();

        // Log final balances
        console.log(
            "Final V2 token balance of migration contract:",
            unaiV2Token.balanceOf(address(migration))
        );
    }
}
