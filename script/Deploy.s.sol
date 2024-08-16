// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Contract as UNAIToken} from "../src/UNAI.sol";
import {StakingVault, IERC20} from "../src/UNAIStaking.sol";
import {UNAIStakeMarketplace} from "../src/UNAIStakeMarketplace.sol";

contract Deploy is Script {
    UNAIToken public unaiToken;
    StakingVault public stakingVault;
    UNAIStakeMarketplace public marketplace;

    uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_PRIVATE_KEY"));

    // You'll need to set this address for the network you're deploying to
    address constant DEX_ROUTER = address(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008);
    // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D //mainnet
    // 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008 //sepolia

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // Deploy UNAI token contract
        unaiToken = new UNAIToken();
        console.log("UNAI Token deployed at:", address(unaiToken));

        // Deploy StakingVault contract
        stakingVault = new StakingVault(IERC20(address(unaiToken)));
        console.log("StakingVault deployed at:", address(stakingVault));

        // Set the staking contract in the UNAI token contract
        unaiToken.setStakingContract(address(stakingVault));

        // Deploy UNAIStakeMarketplace contract with DEX router address
        marketplace =
            new UNAIStakeMarketplace(address(stakingVault), address(unaiToken), DEX_ROUTER);
        console.log("UNAIStakeMarketplace deployed at:", address(marketplace));

        // Authorize the marketplace in the staking contract
        stakingVault.setMarketplaceAuthorization(address(marketplace), true);

        // Note: We no longer need to add pools as the new StakingVault doesn't use them

        vm.stopBroadcast();
    }
}
