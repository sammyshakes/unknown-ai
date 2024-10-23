// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Importing necessary libraries and contracts
import "forge-std/Test.sol";
import {StakingVault, IERC20, SafeERC20} from "../src/UNAIStaking.sol";
import {Contract, IDexRouter} from "../src/UNAI.sol";

contract StakingVaultTest is Test {
    using SafeERC20 for IERC20;

    // Contracts
    StakingVault public stakingVault;
    Contract public stakingToken; // This will serve as both the staking and reward token

    // DEX Router (Mocked)
    address public router = address(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008); // Sepolia
    IDexRouter dexRouter = IDexRouter(router);

    // Users
    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    /**
     * @dev Setup function to initialize contracts and provide liquidity.
     */
    function setUp() public {
        // Deploy the staking token (unaiToken)
        stakingToken = new Contract();

        // Initialize StakingVault with stakingToken (unaiToken)
        stakingVault = new StakingVault(address(stakingToken));

        // Set staking contract in the staking token
        stakingToken.setStakingContract(address(stakingVault));

        // Provide liquidity to the stakingToken's liquidity pool
        uint256 ethAmount = 10 ether;
        uint256 tokenAmount = 10_000_000 * 1e18;

        // Deal some ETH to the owner
        vm.deal(owner, ethAmount * 2);

        // Approve DEX Router to spend staking tokens
        stakingToken.approve(address(dexRouter), tokenAmount);

        // Add liquidity to the DEX
        dexRouter.addLiquidityETH{value: 1 ether}(
            address(stakingToken), tokenAmount, 0, 0, owner, block.timestamp
        );

        // Enable trading if the stakingToken requires it
        stakingToken.enableTrading(1);

        // Remove any trading limits if applicable
        stakingToken.removeLimits();

        // Advance the blockchain to a future block
        vm.roll(block.number + 2);

        // Buy staking tokens for the owner (this contract)
        buyStakingTokens(address(this), 5 ether);

        console.log("Staking token balance:", stakingToken.balanceOf(address(this)) / 1e18);

        // Transfer unaiToken to the StakingVault as initial rewards
        // stakingToken.transfer(address(stakingVault), 5000 * 1e18); // Transfer 5,000 unaiToken

        // // Verify balance
        // assertEq(
        //     stakingToken.balanceOf(address(stakingVault)),
        //     5000 * 1e18,
        //     "StakingVault should have 5,000 unaiToken as rewards (excluding staked tokens)"
        // );
    }

    /**
     * @dev Helper function to buy staking tokens via DEX.
     */
    function buyStakingTokens(address buyer, uint256 ethAmount) private {
        // Deal some ETH to the buyer
        vm.deal(buyer, ethAmount);

        address[] memory path = new address[](2);

        // Buy tokens from the liquidity pool
        vm.startPrank(buyer);
        path[0] = dexRouter.WETH();
        path[1] = address(stakingToken);

        dexRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            0, // accept any amount of tokens
            path,
            buyer,
            block.timestamp
        );
        vm.stopPrank();
    }

    /**
     * @dev Test basic staking and unstaking functionality.
     */
    function test_StakeAndUnstake() public {
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 buys staking tokens
        buyStakingTokens(user1, 1 ether);

        console.log("User1 staking token balance before staking:", stakingToken.balanceOf(user1));

        // User1 stakes staking tokens
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        console.log("User1 staking token balance after staking:", stakingToken.balanceOf(user1));

        // Retrieve stake details
        (
            uint256 amount,
            uint256 startTime,
            uint256 duration,
            uint256 shares,
            uint256 ethRewardDebt,
            uint256 unaiRewardDebt
        ) = stakingVault.userStakes(user1, 0);
        console.log("Staked amount:", amount);
        console.log("Start time:", startTime);
        console.log("Lock duration:", duration);
        console.log("Shares:", shares);
        console.log("ETH Reward Debt:", ethRewardDebt);
        console.log("UNAI Reward Debt:", unaiRewardDebt);

        // Assertions to verify staking
        assertEq(amount, stakeAmount, "Staked amount mismatch");
        assertEq(duration, lockDuration, "Lock duration mismatch");
        // Since SHARE_TIME_FRAME is 90 days, shares should equal amount * lockDuration / SHARE_TIME_FRAME = amount
        assertEq(
            shares,
            stakeAmount,
            "Shares should equal stake amount when lockDuration == SHARE_TIME_FRAME"
        );

        // Approve and deposit UNAI rewards
        vm.startPrank(address(this));
        stakingToken.approve(address(stakingVault), 5000 * 1e18);
        stakingVault.depositUnaiRewards(5000 * 1e18);
        vm.stopPrank();

        // Add ETH rewards to the staking vault
        vm.deal(address(this), 1 ether);
        (bool success1,) = address(stakingVault).call{value: 1 ether}("");
        require(success1, "Failed to send ETH to StakingVault");

        // Warp time to after lock period
        vm.warp(block.timestamp + lockDuration);

        // Capture initial balances before unstaking
        uint256 initialEthBalance = user1.balance;
        uint256 initialUnaiBalance = stakingToken.balanceOf(user1);
        console.log("User1 ETH balance before unstaking:", initialEthBalance);
        console.log("User1 unaiToken balance before unstaking:", initialUnaiBalance);

        // User1 unstakes and claims rewards
        vm.prank(user1);
        stakingVault.unstake(0);

        // Capture final balances after unstaking
        uint256 finalEthBalance = user1.balance;
        uint256 finalUnaiBalance = stakingToken.balanceOf(user1);
        console.log("User1 ETH balance after unstaking:", finalEthBalance);
        console.log("User1 unaiToken balance after unstaking:", finalUnaiBalance);

        // Assertions to verify rewards are received
        assertGt(finalEthBalance, initialEthBalance, "User should have received ETH rewards");
        assertGt(
            finalUnaiBalance,
            initialUnaiBalance + stakeAmount,
            "User should have received UNAI rewards"
        );

        // Ensure the stake has been removed
        vm.expectRevert();
        stakingVault.userStakes(user1, 0);
    }

    /**
     * @dev Test claiming rewards without unstaking.
     */
    function test_ClaimRewards() public {
        uint256 lockDuration = 90 days;

        // User1 buys staking tokens
        buyStakingTokens(user1, 1 ether);

        // Get balance of user1
        uint256 stakeAmount = stakingToken.balanceOf(user1);
        console.log("User1 staking token balance before staking:", stakeAmount);

        // User1 stakes staking tokens
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Approve and deposit UNAI rewards correctly
        vm.startPrank(address(this));
        stakingToken.approve(address(stakingVault), 5000 * 1e18);
        stakingVault.depositUnaiRewards(5000 * 1e18);
        vm.stopPrank();

        // Add ETH rewards to the staking vault
        vm.deal(address(this), 1 ether);
        (bool success,) = address(stakingVault).call{value: 1 ether}("");
        require(success, "Failed to send ETH to StakingVault");

        // Warp time to simulate passage of time
        vm.warp(block.timestamp + 30 days);

        // Capture initial balances before claiming rewards
        uint256 initialEthBalance = user1.balance;
        uint256 initialUnaiBalance = stakingToken.balanceOf(user1);
        console.log("Initial ETH balance:", initialEthBalance);
        console.log("Initial UNAI balance:", initialUnaiBalance);

        // User1 claims rewards without unstaking
        vm.prank(user1);
        stakingVault.claimRewards(0);

        // Capture final balances after claiming rewards
        uint256 finalEthBalance = user1.balance;
        uint256 finalUnaiBalance = stakingToken.balanceOf(user1);
        console.log("Final ETH balance:", finalEthBalance);
        console.log("Final UNAI balance:", finalUnaiBalance);

        // Assertions to verify rewards are received
        assertGt(finalEthBalance, initialEthBalance, "User1 should have received ETH rewards");
        assertGt(finalUnaiBalance, initialUnaiBalance, "User1 should have received UNAI rewards");
    }

    /**
     * @dev Test extending a stake and ensuring reward accuracy.
     */
    function test_ExtendStakeRewardAccuracy() public {
        uint256 initialStakeAmount = 100 * 1e18;
        uint256 initialLockDuration = 30 days;
        uint256 extensionDuration = 60 days;

        // User1 buys staking tokens and stakes
        buyStakingTokens(user1, 1 ether);

        // **Properly approve and deposit UNAI rewards using depositUnaiRewards()**
        vm.startPrank(address(this)); // Assuming 'address(this)' is the depositor
        stakingToken.approve(address(stakingVault), 5000 * 1e18);
        stakingVault.depositUnaiRewards(5000 * 1e18); // Deposit 5,000 UNAI tokens
        vm.stopPrank();

        // User1 stakes staking tokens
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), initialStakeAmount);
        stakingVault.stake(initialStakeAmount, initialLockDuration);
        vm.stopPrank();

        console.log("Initial timestamp:", block.timestamp);
        console.log("Initial total shares:", stakingVault.totalShares());

        // Warp time by 15 days
        vm.warp(block.timestamp + 15 days);

        // Add ETH rewards to the staking vault
        vm.deal(address(this), 1 ether);
        (bool success,) = address(stakingVault).call{value: 1 ether}("");
        require(success, "Failed to send ETH to StakingVault");

        console.log("Timestamp after 15 days:", block.timestamp);
        console.log("Total shares before extension:", stakingVault.totalShares());

        // Check pending rewards before extension
        (uint256 ethPendingBeforeExtension, uint256 unaiPendingBeforeExtension) =
            stakingVault.pendingRewards(user1, 0);
        console.log("Pending ETH rewards before extension:", ethPendingBeforeExtension);
        console.log("Pending UNAI rewards before extension:", unaiPendingBeforeExtension);

        // **Ensure there are pending rewards before extension**
        assertGt(
            ethPendingBeforeExtension,
            0,
            "There should be pending ETH rewards before extending the stake"
        );
        assertGt(
            unaiPendingBeforeExtension,
            0,
            "There should be pending UNAI rewards before extending the stake"
        );

        // Extend the stake
        vm.prank(user1);
        stakingVault.extendStake(0, extensionDuration);

        // Check pending rewards immediately after extension
        (uint256 ethPendingAfterExtension, uint256 unaiPendingAfterExtension) =
            stakingVault.pendingRewards(user1, 0);
        console.log("Pending ETH rewards after extension:", ethPendingAfterExtension);
        console.log("Pending UNAI rewards after extension:", unaiPendingAfterExtension);
        console.log("Total shares after extension:", stakingVault.totalShares());

        // **Ensure rewards have been claimed during extension**
        assertEq(
            ethPendingAfterExtension, 0, "ETH rewards should have been claimed during extension"
        );
        assertEq(
            unaiPendingAfterExtension, 0, "UNAI rewards should have been claimed during extension"
        );

        // Warp time by 75 more days (total 90 days from start)
        vm.warp(block.timestamp + 75 days);

        // Add ETH and UNAI rewards to the staking vault
        vm.deal(address(this), 2 ether);
        (success,) = address(stakingVault).call{value: 2 ether}("");
        require(success, "Failed to send ETH to StakingVault");

        vm.startPrank(address(this));
        stakingToken.approve(address(stakingVault), 5000 * 1e18);
        stakingVault.depositUnaiRewards(5000 * 1e18); // Deposit additional 5,000 UNAI tokens
        vm.stopPrank();

        console.log("Final timestamp:", block.timestamp);
        console.log("Total shares after extension:", stakingVault.totalShares());

        // Check final pending rewards
        (uint256 finalPendingEthRewards, uint256 finalPendingUnaiRewards) =
            stakingVault.pendingRewards(user1, 0);
        console.log("Final pending ETH rewards:", finalPendingEthRewards);
        console.log("Final pending UNAI rewards:", finalPendingUnaiRewards);

        // Claim rewards and check received amount
        uint256 initialEthBalance = user1.balance;
        uint256 initialUnaiBalance = stakingToken.balanceOf(user1);
        vm.prank(user1);
        stakingVault.claimRewards(0);
        uint256 claimedEthRewards = user1.balance - initialEthBalance;
        uint256 claimedUnaiRewards = stakingToken.balanceOf(user1) - initialUnaiBalance;

        console.log("Claimed ETH rewards:", claimedEthRewards);
        console.log("Claimed UNAI rewards:", claimedUnaiRewards);

        // Verify pending rewards are now zero or very small
        (uint256 pendingEthAfterClaim, uint256 pendingUnaiAfterClaim) =
            stakingVault.pendingRewards(user1, 0);
        console.log("Pending ETH rewards after claim:", pendingEthAfterClaim);
        console.log("Pending UNAI rewards after claim:", pendingUnaiAfterClaim);

        assertLe(pendingEthAfterClaim, 1e14, "Pending ETH rewards after claim should be very small");
        assertLe(
            pendingUnaiAfterClaim, 1e14, "Pending UNAI rewards after claim should be very small"
        );
    }

    /**
     * @dev Test that only the owner can deposit UNAI rewards.
     */
    function test_DepositUnaiRewardsByOwner() public {
        //contract balance before deposit
        uint256 contractBalanceBefore = stakingToken.balanceOf(address(stakingVault));
        console.log("Contract balance before deposit:", contractBalanceBefore);

        uint256 rewardAmount = 5000 * 1e18;

        // Owner deposits UNAI rewards
        stakingToken.approve(address(stakingVault), rewardAmount);
        stakingVault.depositUnaiRewards(rewardAmount);

        // Verify the contract's UNAI balance (excluding staked tokens)
        uint256 contractUnaiBalance =
            stakingToken.balanceOf(address(stakingVault)) - stakingVault.totalStaked();
        assertEq(
            contractUnaiBalance - contractBalanceBefore,
            rewardAmount,
            "Contract should have the deposited UNAI rewards"
        );
    }

    /**
     * @dev Test that non-owners can deposit UNAI rewards.
     */
    function test_DepositUnaiRewardsByNonOwner() public {
        //contract balance before deposit
        uint256 contractBalanceBefore = stakingToken.balanceOf(address(stakingVault));
        console.log("Contract balance before deposit:", contractBalanceBefore);

        uint256 rewardAmount = 5000 * 1e18;

        // Transfer UNAI tokens to user1 for testing
        stakingToken.transfer(user1, rewardAmount);

        // User1 deposits UNAI rewards
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), rewardAmount);
        stakingVault.depositUnaiRewards(rewardAmount);
        vm.stopPrank();

        // Verify the contract's UNAI balance (excluding staked tokens)
        uint256 contractUnaiBalance =
            stakingToken.balanceOf(address(stakingVault)) - stakingVault.totalStaked();
        console.log(
            "Contract balance after deposit:", stakingToken.balanceOf(address(stakingVault))
        );
        assertEq(
            contractUnaiBalance - contractBalanceBefore,
            rewardAmount,
            "Contract should have the deposited UNAI rewards from user1"
        );
    }

    /**
     * @dev Test transferring a stake from one user to another.
     */
    function test_TransferStake() public {
        //get contract balance before transfer
        uint256 contractBalanceBefore = stakingToken.balanceOf(address(stakingVault));
        console.log("Contract balance before transfer:", contractBalanceBefore);

        uint256 lockDuration = 90 days;

        // User1 buys staking tokens and stakes
        buyStakingTokens(user1, 1 ether);

        uint256 stakeAmount = stakingToken.balanceOf(user1);
        console.log("User1 staking token balance before staking:", stakeAmount);

        // User1 stakes staking tokens
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // get user 1's stake
        (
            uint256 amount1,
            uint256 startTime1,
            uint256 duration1,
            uint256 shares1,
            uint256 ethRewardDebt1,
            uint256 unaiRewardDebt1
        ) = stakingVault.userStakes(user1, 0);
        console.log("User1's stake details before transfer:");
        console.log("Amount:", amount1);
        console.log("Start time:", startTime1);
        console.log("Duration:", duration1);
        console.log("Shares:", shares1);
        console.log("ETH reward debt:", ethRewardDebt1);
        console.log("UNAI reward debt:", unaiRewardDebt1);

        // Add ETH and UNAI rewards to the staking vault
        vm.deal(address(stakingVault), 1 ether);
        stakingToken.approve(address(stakingVault), 5000 * 1e18);
        stakingVault.depositUnaiRewards(5000 * 1e18); // Deposit 5,000 UNAI tokens

        // Warp time to accumulate surpass the lock duration
        vm.warp(block.timestamp + lockDuration + 1 days);

        // Authorize this contract as a marketplace
        vm.prank(owner);
        stakingVault.setMarketplaceAuthorization(address(this), true);

        // Transfer stake from user1 to user2
        uint256 initialUser1Unai = stakingToken.balanceOf(user1);

        stakingVault.transferStake(user1, user2, 0);

        // Check that user1 no longer has the stake
        vm.expectRevert(); // Expect revert because the stake has been transferred
        stakingVault.userStakes(user1, 0);

        // Check that user2 now has the stake
        (
            uint256 amount2,
            uint256 startTime2,
            uint256 duration2,
            uint256 shares2,
            uint256 ethRewardDebt2,
            uint256 unaiRewardDebt2
        ) = stakingVault.userStakes(user2, 0);

        console.log("User2's stake details after transfer:");
        console.log("Amount:", amount2);
        console.log("Start time:", startTime2);
        console.log("Duration:", duration2);
        console.log("Shares:", shares2);
        console.log("ETH reward debt:", ethRewardDebt2);
        console.log("UNAI reward debt:", unaiRewardDebt2);

        assertEq(amount2, stakeAmount, "Transferred stake amount mismatch");
        assertEq(duration2, lockDuration, "Transferred stake lock duration mismatch");
        assertEq(shares2, stakeAmount, "Transferred stake shares mismatch");

        // Check that pending rewards were transferred to user1
        uint256 finalUser1Unai = stakingToken.balanceOf(user1);

        assertGt(
            finalUser1Unai,
            initialUser1Unai,
            "User1 should have received pending UNAI rewards upon stake transfer"
        );
    }

    /**
     * @dev Test that rewards stop accumulating after the lock duration expires.
     */
    function test_NoRewardsAfterLockExpiration() public {
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 30 days;

        // User1 buys staking tokens
        buyStakingTokens(user1, 1 ether);

        // User1 stakes staking tokens
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Add ETH and UNAI rewards
        // Add ETH rewards to the staking vault
        vm.deal(address(this), 1 ether);
        (bool success,) = address(stakingVault).call{value: 1 ether}("");
        require(success, "Failed to send ETH to StakingVault");

        stakingToken.transfer(address(stakingVault), 1000 * 1e18); // Transfer 1,000 UNAI tokens

        // Warp time to just before expiration
        vm.warp(block.timestamp + 29 days);

        // Check pending rewards just before expiration
        (uint256 ethPendingBefore, uint256 unaiPendingBefore) =
            stakingVault.pendingRewards(user1, 0);

        // Warp time to after expiration
        vm.warp(block.timestamp + 2 days);

        // Check pending rewards after expiration
        (uint256 ethPendingAfter, uint256 unaiPendingAfter) = stakingVault.pendingRewards(user1, 0);

        // Assert that no additional rewards were accumulated after expiration
        assertEq(
            ethPendingAfter,
            ethPendingBefore,
            "ETH rewards should not increase after lock expiration"
        );
        assertEq(
            unaiPendingAfter,
            unaiPendingBefore,
            "UNAI rewards should not increase after lock expiration"
        );
    }

    /**
     * @dev Test that non-owners cannot set marketplace authorization.
     */
    function test_MarketplaceAuthorizationByNonOwner() public {
        // User1 attempts to set marketplace authorization
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        stakingVault.setMarketplaceAuthorization(user1, true);
    }

    /**
     * @dev Test that only the owner can set marketplace authorization.
     */
    function test_MarketplaceAuthorizationByOwner() public {
        // Owner sets marketplace authorization
        stakingVault.setMarketplaceAuthorization(user1, true);

        // Verify authorization
        bool isAuthorized = stakingVault.authorizedMarketplaces(user1);
        assertTrue(isAuthorized, "User1 should be authorized as a marketplace");
    }

    /**
     * @dev Test that staking zero tokens is not allowed.
     */
    function test_StakeWithZeroAmount() public {
        uint256 stakeAmount = 0;
        uint256 lockDuration = 90 days;

        // User1 buys staking tokens
        buyStakingTokens(user1, 1 ether);

        // Attempt to stake zero tokens
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        vm.expectRevert("Amount must be greater than 0");
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();
    }

    /**
     * @dev Test that a user can stake multiple times and each stake is tracked correctly.
     */
    function test_StakeMultipleTimes() public {
        uint256 stakeAmount1 = 100 * 1e18;
        uint256 stakeAmount2 = 200 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 buys staking tokens
        buyStakingTokens(user1, 2 ether);

        // User1 stakes first amount
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount1 + stakeAmount2);
        stakingVault.stake(stakeAmount1, lockDuration);
        stakingVault.stake(stakeAmount2, lockDuration);
        vm.stopPrank();

        // Check first stake
        (uint256 amount1,,,,,) = stakingVault.userStakes(user1, 0);
        assertEq(amount1, stakeAmount1, "First stake amount mismatch");

        // Check second stake
        (uint256 amount2,,,,,) = stakingVault.userStakes(user1, 1);
        assertEq(amount2, stakeAmount2, "Second stake amount mismatch");
    }

    /**
     * @dev Test that unstaking before the lock duration is not allowed.
     */
    function test_UnstakeBeforeLockDuration() public {
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 buys staking tokens
        buyStakingTokens(user1, 1 ether);

        // User1 stakes tokens
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Attempt to unstake before lock duration
        vm.startPrank(user1);
        vm.expectRevert("Lock period not over");
        stakingVault.unstake(0);
        vm.stopPrank();
    }

    /**
     * @dev Test that transferring a stake to the zero address is not allowed.
     */
    function test_TransferStakeToZeroAddress() public {
        uint256 lockDuration = 90 days;

        // User1 buys and stakes tokens
        buyStakingTokens(user1, 1 ether);
        uint256 stakeAmount = stakingToken.balanceOf(user1);
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Authorize this contract as a marketplace
        vm.prank(owner);
        stakingVault.setMarketplaceAuthorization(address(this), true);

        // Attempt to transfer to zero address
        vm.expectRevert("Cannot transfer to zero address");
        stakingVault.transferStake(user1, address(0), 0);
    }

    /**
     * @dev Test that unauthorized callers cannot transfer stakes.
     */
    function test_TransferStakeByUnauthorizedCaller() public {
        uint256 lockDuration = 90 days;

        // User1 buys and stakes tokens
        buyStakingTokens(user1, 1 ether);
        uint256 stakeAmount = stakingToken.balanceOf(user1);
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Attempt to transfer stake by unauthorized user (user3)
        vm.prank(user3);
        vm.expectRevert("Caller is not an authorized marketplace");
        stakingVault.transferStake(user1, user2, 0);
    }

    /**
     * @dev Test adding and removing an authorized marketplace.
     */
    function test_AddAndRemoveAuthorizedMarketplace() public {
        // Initially, user1 is not authorized
        bool isAuthorizedBefore = stakingVault.authorizedMarketplaces(user1);
        assertFalse(isAuthorizedBefore, "User1 should not be authorized initially");

        // Owner authorizes user1
        stakingVault.setMarketplaceAuthorization(user1, true);
        bool isAuthorizedAfter = stakingVault.authorizedMarketplaces(user1);
        assertTrue(isAuthorizedAfter, "User1 should be authorized after authorization");

        // Owner removes authorization for user1
        stakingVault.setMarketplaceAuthorization(user1, false);
        bool isAuthorizedFinal = stakingVault.authorizedMarketplaces(user1);
        assertFalse(isAuthorizedFinal, "User1 should not be authorized after removal");
    }

    /**
     * @dev Test claiming rewards multiple times.
     */
    function test_ClaimRewardsMultipleTimes() public {
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 buys and stakes tokens
        buyStakingTokens(user1, 1 ether);
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Add initial ETH rewards to the staking vault
        vm.deal(address(this), 1 ether);
        (bool success1,) = address(stakingVault).call{value: 1 ether}("");
        require(success1, "Failed to send initial ETH to StakingVault");

        // Approve and deposit UNAI rewards correctly
        vm.startPrank(address(this));
        stakingToken.approve(address(stakingVault), 5000 * 1e18);
        stakingVault.depositUnaiRewards(5000 * 1e18);
        vm.stopPrank();

        // Warp time to accumulate rewards
        vm.warp(block.timestamp + 30 days);

        // First claim
        vm.prank(user1);
        stakingVault.claimRewards(0);

        // Add more ETH and UNAI rewards
        vm.deal(address(this), 1 ether);
        (bool success2,) = address(stakingVault).call{value: 1 ether}("");
        require(success2, "Failed to send additional ETH to StakingVault");

        vm.startPrank(address(this));
        stakingToken.approve(address(stakingVault), 5000 * 1e18);
        stakingVault.depositUnaiRewards(5000 * 1e18);
        vm.stopPrank();

        // Warp time again
        vm.warp(block.timestamp + 30 days);

        // Second claim
        vm.prank(user1);
        stakingVault.claimRewards(0);

        // Capture final ETH and UNAI balances
        uint256 finalEthBalance = user1.balance;
        uint256 finalUnaiBalance = stakingToken.balanceOf(user1);

        // Calculate expected total ETH rewards
        uint256 totalEthRewards = 2 ether;
        uint256 expectedEthRewards = totalEthRewards;

        // Since the totalShares remain the same, the user should receive proportional ETH rewards each time

        // Assert that the final ETH balance increased by approximately the expected rewards
        assertApproxEqAbs(
            finalEthBalance,
            2 ether, // 1 ether from first deposit + 1 ether from second deposit
            1e14, // Allow small discrepancies
            "User1 should receive cumulative ETH rewards correctly"
        );

        // Similarly, check UNAI rewards (exact calculations depend on accUnaiRewardPerShare)
        assertGt(
            finalUnaiBalance,
            100 * 1e18, // Initial stake amount
            "User1 should have received UNAI rewards"
        );
    }

    /**
     * @dev Test that rewards do not double count when claiming multiple times.
     */
    function test_RewardsDoNotDoubleCount() public {
        uint256 lockDuration = 90 days;

        // User1 buys and stakes tokens
        buyStakingTokens(user1, 1 ether);
        uint256 stakeAmount = stakingToken.balanceOf(user1);

        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Approve and deposit initial UNAI rewards
        vm.startPrank(address(this));
        stakingToken.approve(address(stakingVault), 1000 * 1e18);
        stakingVault.depositUnaiRewards(1000 * 1e18);
        vm.stopPrank();

        // Add initial ETH rewards to the staking vault
        vm.deal(address(this), 1 ether);
        (bool success1,) = address(stakingVault).call{value: 1 ether}("");
        require(success1, "Failed to send initial ETH to StakingVault");

        // Warp time to accumulate rewards
        vm.warp(block.timestamp + 30 days);

        // User1 claims rewards first time
        vm.prank(user1);
        stakingVault.claimRewards(0);

        uint256 ethBalanceAfterFirstClaim = user1.balance;
        uint256 unaiBalanceAfterFirstClaim = stakingToken.balanceOf(user1);
        console.log("ETH balance after first claim:", ethBalanceAfterFirstClaim);
        console.log("UNAI balance after first claim:", unaiBalanceAfterFirstClaim);

        // Approve and deposit additional UNAI rewards
        vm.startPrank(address(this));
        stakingToken.approve(address(stakingVault), 1000 * 1e18);
        stakingVault.depositUnaiRewards(1000 * 1e18);
        vm.stopPrank();

        // Add more ETH rewards
        vm.deal(address(this), 1 ether);
        (bool success2,) = address(stakingVault).call{value: 1 ether}("");
        require(success2, "Failed to send additional ETH to StakingVault");

        // Warp time again
        vm.warp(block.timestamp + 30 days);

        // User1 claims rewards second time
        vm.prank(user1);
        stakingVault.claimRewards(0);

        uint256 ethBalanceAfterSecondClaim = user1.balance;
        uint256 unaiBalanceAfterSecondClaim = stakingToken.balanceOf(user1);
        console.log("ETH balance after second claim:", ethBalanceAfterSecondClaim);
        console.log("UNAI balance after second claim:", unaiBalanceAfterSecondClaim);

        // Ensure that second claim only adds new rewards and does not duplicate previous rewards
        assertGt(
            ethBalanceAfterSecondClaim,
            ethBalanceAfterFirstClaim,
            "ETH rewards should accumulate correctly"
        );
        assertGt(
            unaiBalanceAfterSecondClaim,
            unaiBalanceAfterFirstClaim,
            "UNAI rewards should accumulate correctly"
        );
    }

    /**
     * @dev Test that multiple users' stakes and rewards are handled correctly and are isolated.
     */
    function test_MultipleUsersStakes() public {
        uint256 stakeAmount1 = 100 * 1e18;
        uint256 stakeAmount2 = 200 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 buys and stakes tokens
        buyStakingTokens(user1, 1 ether);
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount1);
        stakingVault.stake(stakeAmount1, lockDuration);
        vm.stopPrank();

        // User2 buys and stakes tokens
        buyStakingTokens(user2, 1 ether);
        vm.startPrank(user2);
        stakingToken.approve(address(stakingVault), stakeAmount2);
        stakingVault.stake(stakeAmount2, lockDuration);
        vm.stopPrank();

        // Approve and deposit UNAI rewards
        vm.startPrank(address(this));
        stakingToken.approve(address(stakingVault), 10_000 * 1e18);
        stakingVault.depositUnaiRewards(10_000 * 1e18);
        vm.stopPrank();

        // Add ETH rewards to the staking vault
        vm.deal(address(this), 2 ether);
        (bool success1,) = address(stakingVault).call{value: 2 ether}("");
        require(success1, "Failed to send ETH to StakingVault");

        // Warp time
        vm.warp(block.timestamp + 30 days);

        // User1 claims rewards
        vm.prank(user1);
        stakingVault.claimRewards(0);
        uint256 user1EthBalance = user1.balance;
        uint256 user1UnaiBalance = stakingToken.balanceOf(user1);

        // User2 claims rewards
        vm.prank(user2);
        stakingVault.claimRewards(0);
        uint256 user2EthBalance = user2.balance;
        uint256 user2UnaiBalance = stakingToken.balanceOf(user2);

        // Calculate expected ETH rewards based on shares
        // Total shares = 100 + 200 = 300
        // User1 share = 100, User2 share =200
        // ETH rewards =2 ether
        // User1 should receive (100/300)*2 ether =0.666... ether
        // User2 should receive (200/300)*2 ether =1.333... ether

        // Allow small discrepancies due to integer division
        assertApproxEqAbs(
            user1EthBalance,
            0.666666666666666666 ether,
            1e14, // Allow small discrepancies
            "User1 should receive correct ETH rewards"
        );
        assertApproxEqAbs(
            user2EthBalance,
            1.333333333333333333 ether,
            1e14, // Allow small discrepancies
            "User2 should receive correct ETH rewards"
        );

        // UNAI rewards should also be correctly distributed
        // Assuming accUnaiRewardPerShare is correctly calculated
        assertGt(user1UnaiBalance, stakeAmount1, "User1 should have received UNAI rewards");
        assertGt(user2UnaiBalance, stakeAmount2, "User2 should have received UNAI rewards");
    }

    /**
     * @dev Test staking with maximum possible values.
     */
    function test_StakeWithMaximumValues() public {
        uint256 maxStakeAmount = type(uint256).max;
        uint256 lockDuration = 90 days;

        // User1 buys staking tokens
        buyStakingTokens(user1, 1 ether);

        // Attempt to stake maximum value
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), maxStakeAmount);
        vm.expectRevert(); // Adjust based on your contract's handling
        stakingVault.stake(maxStakeAmount, lockDuration);
        vm.stopPrank();
    }

    /**
     * @dev Test that a user can unstake all their stakes correctly.
     */
    function test_UnstakeAllStakes() public {
        uint256 stakeAmount1 = 100 * 1e18;
        uint256 stakeAmount2 = 200 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 buys and stakes twice
        buyStakingTokens(user1, 2 ether);
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount1 + stakeAmount2);
        stakingVault.stake(stakeAmount1, lockDuration);
        stakingVault.stake(stakeAmount2, lockDuration);
        vm.stopPrank();

        // Warp time
        vm.warp(block.timestamp + lockDuration + 1 days);

        // Unstake first stake
        vm.prank(user1);
        stakingVault.unstake(0);

        // Unstake second stake
        vm.prank(user1);
        stakingVault.unstake(0); // After first unstake, second stake shifts to index 0

        // get user 1's stake
        vm.expectRevert(); // Expect revert because the stake has been removed
        stakingVault.userStakes(user1, 0);

        // Ensure all stakes are removed
        // assertEq(stakingVault.userStakes(user1, 0).amount, 0, "All stakes should be unstaked");
    }

    /**
     * @dev Test emergency withdrawal functionality.
     */
    function test_EmergencyWithdrawal() public {
        uint256 lockDuration = 90 days;

        // User1 buys and stakes tokens
        buyStakingTokens(user1, 1 ether);
        uint256 stakeAmount = stakingToken.balanceOf(user1);

        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Assume the contract has an emergencyWithdrawal function
        // Only the owner can call it
        vm.startPrank(owner);
        stakingVault.emergencyWithdrawal(user1, 0);
        vm.stopPrank();

        // Check that the stake has been removed
        vm.expectRevert();
        stakingVault.userStakes(user1, 0);

        // Check that user1 received their stake back
        uint256 user1Balance = stakingToken.balanceOf(user1);
        assertEq(user1Balance, stakeAmount, "User1 should receive their staked tokens back");
    }

    function test_SmallEthDeposits() public {
        uint256 lockDuration = 90 days;
        uint256 stakeAmount = 100 * 1e18; // 100 tokens

        // User1 buys and stakes tokens
        buyStakingTokens(user1, 1 ether);
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Record initial ETH balance of user1
        uint256 initialEthBalance = user1.balance;

        // Deposit a small ETH reward (e.g., 0.0001 ether)
        uint256 smallEthReward = 0.0001 ether;
        vm.deal(address(this), smallEthReward);
        (bool success,) = address(stakingVault).call{value: smallEthReward}("");
        require(success, "Failed to send ETH to StakingVault");

        // Warp time to accumulate rewards
        vm.warp(block.timestamp + 30 days);

        // User1 claims rewards
        vm.prank(user1);
        stakingVault.claimRewards(0);

        // Record final ETH balance of user1
        uint256 finalEthBalance = user1.balance;

        // Correct calculation of the expected ETH reward
        uint256 expectedReward = smallEthReward;

        // Assert that the final ETH balance increased by approximately the expected reward
        assertApproxEqAbs(
            finalEthBalance,
            initialEthBalance + expectedReward,
            1 wei,
            "User1 should receive the correct small ETH reward"
        );
    }
}
