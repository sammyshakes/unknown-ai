// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Contract, IDexRouter} from "../src/UNAI.sol";
import "../src/UNAIStaking.sol";
import {UNAIStakeMarketplace} from "../src/UNAIStakeMarketplace.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
}

contract StakeMarketplaceTest is Test {
    StakingVault public stakingVault;
    Contract public unaiToken;
    UNAIStakeMarketplace public marketplace;
    IWETH public weth;
    IDexRouter public dexRouter;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public constant DEX_ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;

    function setUp() public {
        console.log("Setting up test environment...");
        unaiToken = new Contract();
        stakingVault = new StakingVault(IERC20(address(unaiToken)));
        marketplace =
            new UNAIStakeMarketplace(address(stakingVault), address(unaiToken), DEX_ROUTER);
        dexRouter = IDexRouter(DEX_ROUTER);
        weth = IWETH(dexRouter.WETH());

        unaiToken.setStakingContract(address(stakingVault));
        stakingVault.setMarketplaceAuthorization(address(marketplace), true);

        // Setup initial conditions
        stakingVault.addPool(30 days, 10, StakingVault.LockupDuration.ThreeMonths);
        stakingVault.addPool(90 days, 5, StakingVault.LockupDuration.SixMonths);
        stakingVault.addPool(365 days, 15, StakingVault.LockupDuration.TwelveMonths);
        unaiToken.enableTrading(1);
        unaiToken.removeLimits();

        vm.roll(block.number + 2);

        // Mint tokens to users and add liquidity
        uint256 initialTokenAmount = 1_000_000 * 1e18;
        unaiToken.transfer(user1, initialTokenAmount);
        unaiToken.transfer(user2, initialTokenAmount);
        addLiquidity(initialTokenAmount, 1000 ether);

        console.log("Test environment set up complete.");
        console.log("User1 balance:", unaiToken.balanceOf(user1) / 1e18);
        console.log("User2 balance:", unaiToken.balanceOf(user2) / 1e18);

        // Fund the marketplace with ETH
        vm.deal(address(marketplace), 100 ether);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {
        unaiToken.approve(DEX_ROUTER, tokenAmount);
        dexRouter.addLiquidityETH{value: ethAmount}(
            address(unaiToken), tokenAmount, 0, 0, address(this), block.timestamp
        );
    }

    function testCreateListingWithTimestamp() public {
        console.log("Testing create listing with timestamp...");
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
        uint256 listingTimestamp = block.timestamp;
        marketplace.createListing(poolId, 0, 150 * 1e18);
        vm.stopPrank();

        // Check if listing was created correctly
        (
            address seller,
            uint256 listedPoolId,
            uint256 stakeId,
            uint256 price,
            bool active,
            bool fulfilled,
            uint256 timestamp
        ) = marketplace.listings(0);
        console.log("Listing created. Seller:", seller);
        console.log("Listed Pool ID:", listedPoolId);
        console.log("Stake ID:", stakeId);
        console.log("Price:", price / 1e18);
        console.log("Active:", active);
        console.log("Fulfilled:", fulfilled);
        console.log("Timestamp:", timestamp);

        assertEq(seller, user1);
        assertEq(listedPoolId, poolId);
        assertEq(stakeId, 0);
        assertEq(price, 150 * 1e18);
        assertTrue(active);
        assertFalse(fulfilled);
        assertEq(timestamp, listingTimestamp);
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
        (,,,, bool active, bool fulfilled) = marketplace.getListing(0);
        console.log("Listing active status after cancellation:", active);
        console.log("Listing fulfilled status after cancellation:", fulfilled);
        assertFalse(active);
        assertFalse(fulfilled);
    }

    function testFulfillListingWithFee() public {
        console.log("Testing fulfill listing with fee...");
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

        // Record initial balances
        uint256 initialUser1Balance = unaiToken.balanceOf(user1);
        uint256 initialUser2Balance = unaiToken.balanceOf(user2);
        uint256 initialMarketplaceEthBalance = address(marketplace).balance;

        // User2 fulfills the listing
        vm.startPrank(user2);
        console.log("User2 fulfilling listing...");
        unaiToken.approve(address(marketplace), listingPrice);
        marketplace.fulfillListing(0);
        vm.stopPrank();

        // Check if listing was fulfilled and stake was transferred
        (,,,, bool active, bool fulfilled) = marketplace.getListing(0);
        console.log("Listing active status after fulfillment:", active);
        console.log("Listing fulfilled status after fulfillment:", fulfilled);

        (uint256 amount,, address stakeOwner,) = stakingVault.stakes(user2, poolId, 0);
        console.log("New stake owner:", stakeOwner);
        console.log("Stake amount:", amount / 1e18);

        assertEq(stakeOwner, user2);
        assertEq(amount, stakeAmount);
        assertFalse(active);
        assertTrue(fulfilled);

        // Check if payment was transferred correctly
        uint256 fee = (listingPrice * marketplace.marketplaceFee()) / 10_000;
        uint256 sellerAmount = listingPrice - fee;

        console.log("User1 balance after sale:", unaiToken.balanceOf(user1) / 1e18);
        console.log("User2 balance after purchase:", unaiToken.balanceOf(user2) / 1e18);
        console.log("Marketplace ETH balance after sale:", address(marketplace).balance / 1e18);

        assertEq(unaiToken.balanceOf(user1), initialUser1Balance + sellerAmount);
        assertEq(unaiToken.balanceOf(user2), initialUser2Balance - listingPrice);

        // The marketplace's ETH balance should have increased due to the fee swap
        assertTrue(address(marketplace).balance > initialMarketplaceEthBalance);
    }

    function testSetMarketplaceFee() public {
        console.log("Testing set marketplace fee...");
        uint256 newFee = 200; // 2%
        marketplace.setMarketplaceFee(newFee);
        assertEq(marketplace.marketplaceFee(), newFee);
        console.log("New marketplace fee set:", newFee);
    }

    function testGetActiveListings() public {
        console.log("Testing get active listings...");
        uint256 poolId = 0;
        uint256 stakeAmount = 100 * 1e18;

        // User1 stakes tokens and creates listings
        vm.startPrank(user1);
        console.log("User1 staking tokens and creating listings...");
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(poolId, stakeAmount);
        marketplace.createListing(poolId, 0, 150 * 1e18);

        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(poolId, stakeAmount);
        marketplace.createListing(poolId, 1, 200 * 1e18);
        vm.stopPrank();

        // Get all active listings
        UNAIStakeMarketplace.Listing[] memory activeListings = marketplace.getActiveListings();
        console.log("Number of active listings:", activeListings.length);
        assertEq(activeListings.length, 2);

        for (uint256 i = 0; i < activeListings.length; i++) {
            console.log("Active Listing", i);
            console.log("Seller:", activeListings[i].seller);
            console.log("Pool ID:", activeListings[i].poolId);
            console.log("Stake ID:", activeListings[i].stakeId);
            console.log("Price:", activeListings[i].price / 1e18);
            console.log("Active:", activeListings[i].active);
            console.log("Fulfilled:", activeListings[i].fulfilled);
            assertTrue(activeListings[i].active);
            assertFalse(activeListings[i].fulfilled);
        }
    }

    function testGetFulfilledListings() public {
        console.log("Testing get fulfilled listings...");
        uint256 poolId = 0;
        uint256 stakeAmount = 100 * 1e18;
        uint256 listingPrice = 150 * 1e18;

        // User1 stakes tokens and creates listings
        vm.startPrank(user1);
        console.log("User1 staking tokens and creating listings...");
        unaiToken.approve(address(stakingVault), stakeAmount * 2);
        stakingVault.stake(poolId, stakeAmount);
        marketplace.createListing(poolId, 0, listingPrice);

        stakingVault.stake(poolId, stakeAmount);
        marketplace.createListing(poolId, 1, listingPrice);
        vm.stopPrank();

        // User2 fulfills the first listing
        vm.startPrank(user2);
        console.log("User2 fulfilling listing...");
        unaiToken.approve(address(marketplace), listingPrice);
        marketplace.fulfillListing(0);
        vm.stopPrank();

        // Get all fulfilled listings
        UNAIStakeMarketplace.Listing[] memory fulfilledListings = marketplace.getFulfilledListings();
        console.log("Number of fulfilled listings:", fulfilledListings.length);
        assertEq(fulfilledListings.length, 1);

        for (uint256 i = 0; i < fulfilledListings.length; i++) {
            console.log("Fulfilled Listing", i);
            console.log("Seller:", fulfilledListings[i].seller);
            console.log("Pool ID:", fulfilledListings[i].poolId);
            console.log("Stake ID:", fulfilledListings[i].stakeId);
            console.log("Price:", fulfilledListings[i].price / 1e18);
            console.log("Active:", fulfilledListings[i].active);
            console.log("Fulfilled:", fulfilledListings[i].fulfilled);
            assertFalse(fulfilledListings[i].active);
            assertTrue(fulfilledListings[i].fulfilled);
        }
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

    function testWithdrawETH() public {
        console.log("Testing withdraw ETH...");

        // First, we need to ensure there's some ETH in the contract
        uint256 amount = 1 ether;
        vm.deal(address(marketplace), amount);

        uint256 initialOwnerBalance = address(this).balance;
        uint256 initialMarketplaceBalance = address(marketplace).balance;

        marketplace.withdrawETH();

        assertEq(address(marketplace).balance, 0);
        assertEq(address(this).balance, initialOwnerBalance + initialMarketplaceBalance);
        console.log("ETH withdrawn successfully.");
    }

    receive() external payable {}
}
