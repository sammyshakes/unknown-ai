// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {Contract as UNAIToken} from "../src/UNAI.sol";
import {StakingVault, IERC20} from "../src/UNAIStaking.sol";
import {UNAIStakeMarketplace} from "../src/UNAIStakeMarketplace.sol";

contract Deploy is Script {
    UNAIToken public unaiToken;
    StakingVault public stakingVault;
    UNAIStakeMarketplace public marketplace;

    uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_PRIVATE_KEY"));

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

        // Deploy UNAIStakeMarketplace contract
        marketplace = new UNAIStakeMarketplace(address(stakingVault), address(unaiToken));
        console.log("UNAIStakeMarketplace deployed at:", address(marketplace));

        // Authorize the marketplace in the staking contract
        stakingVault.setMarketplaceAuthorization(address(marketplace), true);

        // Add pools to the staking vault
        stakingVault.addPool(30 days, 10, StakingVault.LockupDuration.ThreeMonths);
        stakingVault.addPool(90 days, 5, StakingVault.LockupDuration.SixMonths);
        stakingVault.addPool(365 days, 20, StakingVault.LockupDuration.TwelveMonths);
        console.log("Staking pools added.");

        vm.stopBroadcast();
    }
}
