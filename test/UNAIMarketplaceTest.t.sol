// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Contract} from "../src/UNAI.sol";
import "../src/UNAIStaking.sol";
import "../src/UNAIStakeMarketplace.sol";

contract StakeMarketplaceTest is Test {
    StakingVault public stakingVault;
    Contract public unaiToken;
    UNAIStakeMarketplace public marketplace;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    function setUp() public {
        console.log("Setting up test environment...");
        unaiToken = new Contract();
        stakingVault = new StakingVault(IERC20(address(unaiToken)));
        marketplace = new UNAIStakeMarketplace(address(stakingVault), address(unaiToken));

        unaiToken.setStakingContract(address(stakingVault));
        stakingVault.setMarketplaceAuthorization(address(marketplace), true);

        // Setup initial conditions
        stakingVault.addPool(30 days, 10);
        unaiToken.enableTrading(1);
        unaiToken.removeLimits();

        vm.roll(block.number + 2);

        // Mint tokens to users
        unaiToken.transfer(user1, 1000 * 1e18);
        unaiToken.transfer(user2, 1000 * 1e18);
        console.log("Test environment set up complete.");
        console.log("User1 balance:", unaiToken.balanceOf(user1) / 1e18);
        console.log("User2 balance:", unaiToken.balanceOf(user2) / 1e18);
    }

    function testCreateListing() public {
        console.log("Testing create listing...");
        uint256 poolId = 0;
        uint256 stakeAmount = 100 * 1e18;

        // User1 stakes tokens
        vm.startPrank(user1);
        console.log("User1 approving tokens for staking...");
        unaiToken.approve(address(stakingVault), stakeAmount);
        console.log("User1 staking tokens...");
        stakingVault.stake(poolId, stakeAmount);

        // User1 creates a listing
        console.log("User1 creating listing...");
        marketplace.createListing(poolId, 0, 150 * 1e18);
        vm.stopPrank();

        // Check if listing was created correctly
        (address seller, uint256 listedPoolId, uint256 stakeId, uint256 price, bool active) =
            marketplace.listings(0);
        console.log("Listing created. Seller:", seller);
        console.log("Listed Pool ID:", listedPoolId);
        console.log("Stake ID:", stakeId);
        console.log("Price:", price / 1e18);
        console.log("Active:", active);

        assertEq(seller, user1);
        assertEq(listedPoolId, poolId);
        assertEq(stakeId, 0);
        assertEq(price, 150 * 1e18);
        assertTrue(active);
    }

    function testCancelListing() public {
        console.log("Testing cancel listing...");
        uint256 poolId = 0;
        uint256 stakeAmount = 100 * 1e18;

        // User1 stakes tokens and creates a listing
        vm.startPrank(user1);
        console.log("User1 staking tokens and creating listing...");
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(poolId, stakeAmount);
        marketplace.createListing(poolId, 0, 150 * 1e18);

        // User1 cancels the listing
        console.log("User1 cancelling listing...");
        marketplace.cancelListing(0);
        vm.stopPrank();

        // Check if listing was cancelled
        (,,,, bool active) = marketplace.listings(0);
        console.log("Listing active status after cancellation:", active);
        assertFalse(active);
    }

    function testFulfillListing() public {
        console.log("Testing fulfill listing...");
        uint256 poolId = 0;
        uint256 stakeAmount = 100 * 1e18;
        uint256 listingPrice = 150 * 1e18;

        // User1 stakes tokens and creates a listing
        vm.startPrank(user1);
        console.log("User1 staking tokens and creating listing...");
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(poolId, stakeAmount);
        marketplace.createListing(poolId, 0, listingPrice);
        vm.stopPrank();

        // User2 fulfills the listing
        vm.startPrank(user2);
        console.log("User2 fulfilling listing...");
        unaiToken.approve(address(marketplace), listingPrice);
        marketplace.fulfillListing(0);
        vm.stopPrank();

        // Check if listing was fulfilled and stake was transferred
        (,,,, bool active) = marketplace.listings(0);
        console.log("Listing active status after fulfillment:", active);

        (uint256 amount,, address stakeOwner,) = stakingVault.stakes(user2, poolId, 0);
        console.log("New stake owner:", stakeOwner);
        console.log("Stake amount:", amount / 1e18);

        assertEq(stakeOwner, user2);
        assertEq(amount, stakeAmount);

        // Check if payment was transferred
        console.log("User1 balance after sale:", unaiToken.balanceOf(user1) / 1e18);
        console.log("User2 balance after purchase:", unaiToken.balanceOf(user2) / 1e18);
        assertEq(unaiToken.balanceOf(user1), 1050 * 1e18);
        assertEq(unaiToken.balanceOf(user2), 850 * 1e18);
    }

    function testUnauthorizedListingCreation() public {
        console.log("Testing unauthorized listing creation...");
        uint256 poolId = 0;

        // User2 tries to create a listing for a stake they don't own
        vm.prank(user2);
        console.log("User2 attempting to create unauthorized listing...");
        vm.expectRevert();
        marketplace.createListing(poolId, 0, 100 * 1e18);
        console.log("Unauthorized listing creation reverted as expected.");
    }

    function testUnauthorizedListingCancellation() public {
        console.log("Testing unauthorized listing cancellation...");
        uint256 poolId = 0;
        uint256 stakeAmount = 100 * 1e18;

        // User1 stakes tokens and creates a listing
        vm.startPrank(user1);
        console.log("User1 staking tokens and creating listing...");
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(poolId, stakeAmount);
        marketplace.createListing(poolId, 0, 150 * 1e18);
        vm.stopPrank();

        // User2 tries to cancel User1's listing
        vm.prank(user2);
        console.log("User2 attempting to cancel User1's listing...");
        vm.expectRevert("Not the seller of this listing");
        marketplace.cancelListing(0);
        console.log("Unauthorized listing cancellation reverted as expected.");
    }

    function testFulfillInactiveListing() public {
        console.log("Testing fulfill inactive listing...");
        uint256 poolId = 0;
        uint256 stakeAmount = 100 * 1e18;

        // User1 stakes tokens and creates a listing
        vm.startPrank(user1);
        console.log("User1 staking tokens, creating and cancelling listing...");
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(poolId, stakeAmount);
        marketplace.createListing(poolId, 0, 150 * 1e18);
        marketplace.cancelListing(0);
        vm.stopPrank();

        // User2 tries to fulfill a cancelled listing
        vm.prank(user2);
        console.log("User2 attempting to fulfill cancelled listing...");
        vm.expectRevert("Listing is not active");
        marketplace.fulfillListing(0);
        console.log("Fulfilling inactive listing reverted as expected.");
    }

    function testUpdateStakingVault() public {
        console.log("Testing update staking vault...");
        address newStakingVault = address(0x123);
        console.log("Updating staking vault to:", newStakingVault);
        marketplace.updateStakingVault(newStakingVault);
        assertEq(address(marketplace.stakingVault()), newStakingVault);
        console.log("Staking vault updated successfully.");
    }

    function testUpdatePaymentToken() public {
        console.log("Testing update payment token...");
        address newPaymentToken = address(0x456);
        console.log("Updating payment token to:", newPaymentToken);
        marketplace.updatePaymentToken(newPaymentToken);
        assertEq(address(marketplace.paymentToken()), newPaymentToken);
        console.log("Payment token updated successfully.");
    }

    function testUnauthorizedStakingVaultUpdate() public {
        console.log("Testing unauthorized staking vault update...");
        vm.prank(user1);
        console.log("User1 attempting to update staking vault...");
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        marketplace.updateStakingVault(address(0x123));
        console.log("Unauthorized staking vault update reverted as expected.");
    }

    function testUnauthorizedPaymentTokenUpdate() public {
        console.log("Testing unauthorized payment token update...");
        vm.prank(user1);
        console.log("User1 attempting to update payment token...");
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        marketplace.updatePaymentToken(address(0x456));
        console.log("Unauthorized payment token update reverted as expected.");
    }
}
