// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
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
    }

    function testCreateListing() public {
        uint256 poolId = 0;
        uint256 stakeAmount = 100 * 1e18;

        // User1 stakes tokens
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(poolId, stakeAmount);

        // User1 creates a listing
        marketplace.createListing(poolId, 0, 150 * 1e18);
        vm.stopPrank();

        // Check if listing was created correctly
        (address seller, uint256 listedPoolId, uint256 stakeId, uint256 price, bool active) =
            marketplace.listings(0);
        assertEq(seller, user1);
        assertEq(listedPoolId, poolId);
        assertEq(stakeId, 0);
        assertEq(price, 150 * 1e18);
        assertTrue(active);
    }

    function testCancelListing() public {
        uint256 poolId = 0;
        uint256 stakeAmount = 100 * 1e18;

        // User1 stakes tokens and creates a listing
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(poolId, stakeAmount);
        marketplace.createListing(poolId, 0, 150 * 1e18);

        // User1 cancels the listing
        marketplace.cancelListing(0);
        vm.stopPrank();

        // Check if listing was cancelled
        (,,,, bool active) = marketplace.listings(0);
        assertFalse(active);
    }

    function testFulfillListing() public {
        uint256 poolId = 0;
        uint256 stakeAmount = 100 * 1e18;
        uint256 listingPrice = 150 * 1e18;

        // User1 stakes tokens and creates a listing
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(poolId, stakeAmount);
        marketplace.createListing(poolId, 0, listingPrice);
        vm.stopPrank();

        // User2 fulfills the listing
        vm.startPrank(user2);
        unaiToken.approve(address(marketplace), listingPrice);
        marketplace.fulfillListing(0);
        vm.stopPrank();

        // Check if listing was fulfilled and stake was transferred
        (,,,, bool active) = marketplace.listings(0);
        assertFalse(active);

        (uint256 amount,, address stakeOwner,) = stakingVault.stakes(user2, poolId, 0);
        assertEq(stakeOwner, user2);
        assertEq(amount, stakeAmount);

        // Check if payment was transferred
        assertEq(unaiToken.balanceOf(user1), 1050 * 1e18);
        assertEq(unaiToken.balanceOf(user2), 850 * 1e18);
    }

    function testUnauthorizedListingCreation() public {
        uint256 poolId = 0;

        // User2 tries to create a listing for a stake they don't own
        vm.prank(user2);
        vm.expectRevert();
        marketplace.createListing(poolId, 0, 100 * 1e18);
    }

    function testUnauthorizedListingCancellation() public {
        uint256 poolId = 0;
        uint256 stakeAmount = 100 * 1e18;

        // User1 stakes tokens and creates a listing
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(poolId, stakeAmount);
        marketplace.createListing(poolId, 0, 150 * 1e18);
        vm.stopPrank();

        // User2 tries to cancel User1's listing
        vm.prank(user2);
        vm.expectRevert("Not the seller of this listing");
        marketplace.cancelListing(0);
    }

    function testFulfillInactiveListing() public {
        uint256 poolId = 0;
        uint256 stakeAmount = 100 * 1e18;

        // User1 stakes tokens and creates a listing
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(poolId, stakeAmount);
        marketplace.createListing(poolId, 0, 150 * 1e18);
        marketplace.cancelListing(0);
        vm.stopPrank();

        // User2 tries to fulfill a cancelled listing
        vm.prank(user2);
        vm.expectRevert("Listing is not active");
        marketplace.fulfillListing(0);
    }

    function testUpdateStakingVault() public {
        address newStakingVault = address(0x123);
        marketplace.updateStakingVault(newStakingVault);
        assertEq(address(marketplace.stakingVault()), newStakingVault);
    }

    function testUpdatePaymentToken() public {
        address newPaymentToken = address(0x456);
        marketplace.updatePaymentToken(newPaymentToken);
        assertEq(address(marketplace.paymentToken()), newPaymentToken);
    }

    function testUnauthorizedStakingVaultUpdate() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        marketplace.updateStakingVault(address(0x123));
    }

    function testUnauthorizedPaymentTokenUpdate() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        marketplace.updatePaymentToken(address(0x456));
    }
}
