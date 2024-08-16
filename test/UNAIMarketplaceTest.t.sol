// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Contract, IDexRouter} from "../src/UNAI.sol";
import {StakingVault, IERC20} from "../src/UNAIStaking.sol";
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

    function testCreateAndFulfillListing() public {
        console.log("Testing create and fulfill listing...");
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 stakes tokens
        vm.startPrank(user1);
        console.log("User1 approving tokens for staking...");
        unaiToken.approve(address(stakingVault), stakeAmount);
        console.log("User1 staking tokens...");
        stakingVault.stake(stakeAmount, lockDuration);

        // User1 creates a listing
        console.log("User1 creating listing...");
        marketplace.createListing(0, 150 * 1e18);
        vm.stopPrank();

        // Check if listing was created correctly
        (address seller, uint256 stakeId, uint256 price, bool active, bool fulfilled) =
            marketplace.getListing(0);
        console.log("Listing created. Seller:", seller);
        console.log("Stake ID:", stakeId);
        console.log("Price:", price / 1e18);
        console.log("Active:", active);
        console.log("Fulfilled:", fulfilled);

        assertEq(seller, user1);
        assertEq(stakeId, 0);
        assertEq(price, 150 * 1e18);
        assertTrue(active);
        assertFalse(fulfilled);

        // User2 fulfills the listing
        vm.startPrank(user2);
        console.log("User2 approving tokens for purchase...");
        unaiToken.approve(address(marketplace), 150 * 1e18);
        console.log("User2 fulfilling listing...");
        marketplace.fulfillListing(0);
        vm.stopPrank();

        // Check if listing was fulfilled
        (,,, active, fulfilled) = marketplace.getListing(0);
        console.log("Listing active status after fulfillment:", active);
        console.log("Listing fulfilled status after fulfillment:", fulfilled);
        assertFalse(active);
        assertTrue(fulfilled);

        // Check if stake was transferred
        (uint256 amount,,,,) = stakingVault.userStakes(user2, 0);
        console.log("User2 stake amount after fulfillment:", amount / 1e18);
        assertEq(amount, stakeAmount);
    }

    function testCancelListing() public {
        console.log("Testing cancel listing...");
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 stakes tokens and creates a listing
        vm.startPrank(user1);
        console.log("User1 staking tokens and creating listing...");
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        marketplace.createListing(0, 150 * 1e18);

        // User1 cancels the listing
        console.log("User1 cancelling listing...");
        marketplace.cancelListing(0);
        vm.stopPrank();

        // Check if listing was cancelled
        (,,, bool active, bool fulfilled) = marketplace.getListing(0);
        console.log("Listing active status after cancellation:", active);
        console.log("Listing fulfilled status after cancellation:", fulfilled);
        assertFalse(active);
        assertFalse(fulfilled);
    }

    function testUpdateListingPrice() public {
        console.log("Testing update listing price...");
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 stakes tokens and creates a listing
        vm.startPrank(user1);
        console.log("User1 staking tokens and creating listing...");
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        marketplace.createListing(0, 150 * 1e18);

        // User1 updates the listing price
        console.log("User1 updating listing price...");
        marketplace.updateListingPrice(0, 200 * 1e18);
        vm.stopPrank();

        // Check if listing price was updated
        (,, uint256 newPrice,,) = marketplace.getListing(0);
        console.log("New listing price:", newPrice / 1e18);
        assertEq(newPrice, 200 * 1e18);
    }

    function testGetActiveListings() public {
        console.log("Testing get active listings...");
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 stakes tokens and creates listings
        vm.startPrank(user1);
        console.log("User1 staking tokens and creating listings...");
        unaiToken.approve(address(stakingVault), stakeAmount * 2);
        stakingVault.stake(stakeAmount, lockDuration);
        marketplace.createListing(0, 150 * 1e18);

        stakingVault.stake(stakeAmount, lockDuration);
        marketplace.createListing(1, 200 * 1e18);
        vm.stopPrank();

        // Get all active listings
        UNAIStakeMarketplace.Listing[] memory activeListings = marketplace.getActiveListings();
        console.log("Number of active listings:", activeListings.length);
        assertEq(activeListings.length, 2);

        for (uint256 i = 0; i < activeListings.length; i++) {
            console.log("Active Listing", i);
            console.log("Seller:", activeListings[i].seller);
            console.log("Stake ID:", activeListings[i].stakeId);
            console.log("Price:", activeListings[i].price / 1e18);
            console.log("Active:", activeListings[i].active);
            console.log("Fulfilled:", activeListings[i].fulfilled);
            assertTrue(activeListings[i].active);
            assertFalse(activeListings[i].fulfilled);
        }
    }

    function testUnauthorizedListingCreation() public {
        console.log("Testing unauthorized listing creation...");

        // User2 tries to create a listing for a stake they don't own
        vm.prank(user2);
        console.log("User2 attempting to create unauthorized listing...");
        vm.expectRevert();
        marketplace.createListing(0, 100 * 1e18);
        console.log("Unauthorized listing creation reverted as expected.");
    }

    function testUnauthorizedListingCancellation() public {
        console.log("Testing unauthorized listing cancellation...");
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 stakes tokens and creates a listing
        vm.startPrank(user1);
        console.log("User1 staking tokens and creating listing...");
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        marketplace.createListing(0, 150 * 1e18);
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
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 stakes tokens and creates a listing
        vm.startPrank(user1);
        console.log("User1 staking tokens, creating and cancelling listing...");
        unaiToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        marketplace.createListing(0, 150 * 1e18);
        marketplace.cancelListing(0);
        vm.stopPrank();

        // User2 tries to fulfill a cancelled listing
        vm.prank(user2);
        console.log("User2 attempting to fulfill cancelled listing...");
        vm.expectRevert("Listing is not active");
        marketplace.fulfillListing(0);
        console.log("Fulfilling inactive listing reverted as expected.");
    }
}
