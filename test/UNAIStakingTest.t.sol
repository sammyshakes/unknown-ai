// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Importing necessary libraries and contracts
import "forge-std/Test.sol";
import {StakingVault, IERC20, SafeERC20} from "../src/UNAIStaking.sol";
import {Contract, IDexRouter} from "../src/UNAI.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract StakingVaultTest is Test {
    using SafeERC20 for IERC20;

    // Contracts
    StakingVault public stakingVault;
    Contract public stakingToken;
    ERC20Mock public rewardToken1;
    ERC20Mock public rewardToken2; // For tests with multiple reward tokens

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
        // Deploy separate staking and reward tokens
        stakingToken = new Contract();
        rewardToken1 = new ERC20Mock();
        // rewardToken2 can be deployed in specific tests when needed

        // Initialize StakingVault with stakingToken (unaiToken)
        stakingVault = new StakingVault(address(stakingToken));

        // Set staking contract
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

        // **Important:** Do NOT add unaiToken as a reward token here
        // It's already initialized as a reward token in the StakingVault constructor

        // Deploy and mint RewardToken1
        rewardToken1.mint(address(this), 10_000 * 1e18); // Mint 10,000 RT1

        // Buy staking tokens for the owner (this contract)
        buyStakingTokens(address(this), 5 ether);

        // Transfer RewardToken1 to the StakingVault as initial rewards
        rewardToken1.transfer(address(stakingVault), 5000 * 1e18); // Transfer 5,000 RT1
        // add RewardToken1 as a reward token
        stakingVault.addERC20Reward(address(rewardToken1));

        // Verify balance
        assertEq(
            rewardToken1.balanceOf(address(stakingVault)),
            5000 * 1e18,
            "StakingVault should have 5,000 RewardToken1"
        );

        // Additionally, ensure that the initial reward token (unaiToken) is set correctly
        assertEq(
            stakingVault.rewardTokenList(0),
            address(stakingToken),
            "Initial reward token should be unaiToken"
        );
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
     * @dev Helper function to sum ERC20 rewards.
     */
    function sumERC20Rewards(uint256[] memory erc20Rewards) internal pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < erc20Rewards.length; i++) {
            sum += erc20Rewards[i];
        }
        return sum;
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
        (uint256 amount, uint256 startTime, uint256 duration, uint256 shares, uint256 ethRewardDebt)
        = stakingVault.userStakes(user1, 0);
        console.log("Staked amount:", amount);
        console.log("Start time:", startTime);
        console.log("Lock duration:", duration);
        console.log("Shares:", shares);
        console.log("ETH Reward Debt:", ethRewardDebt);

        // Assertions to verify staking
        assertEq(amount, stakeAmount, "Staked amount mismatch");
        assertEq(duration, lockDuration, "Lock duration mismatch");
        // Since SHARE_TIME_FRAME is 90 days, shares should equal amount * lockDuration / SHARE_TIME_FRAME = amount * 90 / 90 = amount
        assertEq(
            shares,
            stakeAmount,
            "Shares should equal stake amount when lockDuration == SHARE_TIME_FRAME"
        );

        // Add ETH rewards to the staking vault
        vm.deal(address(stakingVault), 1 ether);

        // Transfer some rewardToken1 to the staking vault for distribution
        rewardToken1.mint(address(stakingVault), 5000 * 1e18); // Transfer 5000 reward tokens

        // Warp time to after lock period
        vm.warp(block.timestamp + lockDuration);

        // Capture initial balances before unstaking
        uint256 initialEthBalance = user1.balance;
        uint256 initialErc20Balance = rewardToken1.balanceOf(user1);
        console.log("User1 ETH balance before unstaking:", initialEthBalance);
        console.log("User1 ERC20 reward balance before unstaking:", initialErc20Balance);

        // User1 unstakes and claims rewards
        vm.prank(user1);
        stakingVault.unstake(0);

        // Capture final balances after unstaking
        uint256 finalEthBalance = user1.balance;
        uint256 finalErc20Balance = rewardToken1.balanceOf(user1);
        console.log("User1 ETH balance after unstaking:", finalEthBalance);
        console.log("User1 ERC20 reward balance after unstaking:", finalErc20Balance);

        // Assertions to verify rewards are received
        assertGt(finalEthBalance, initialEthBalance, "User should have received ETH rewards");
        assertGt(finalErc20Balance, initialErc20Balance, "User should have received ERC20 rewards");

        // Ensure the stake has been removed
        vm.expectRevert(); // Expect revert because the stake has been removed
        stakingVault.userStakes(user1, 0);
    }

    /**
     * @dev Test claiming rewards without unstaking.
     */
    function test_ClaimRewards() public {
        // uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 buys staking tokens
        buyStakingTokens(user1, 1 ether);

        //get balance of user1
        uint256 stakeAmount = stakingToken.balanceOf(user1);
        console.log("User1 staking token balance before staking:", stakeAmount);

        // User1 stakes staking tokens
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Add ETH rewards to the staking vault
        vm.deal(address(stakingVault), 1 ether);

        // Warp time to simulate passage of time
        vm.warp(block.timestamp + 30 days);

        // Capture initial balances before claiming rewards
        uint256 initialEthBalance = user1.balance;
        uint256 initialErc20Balance = rewardToken1.balanceOf(user1);
        console.log("Initial ETH balance:", initialEthBalance);
        console.log("Initial ERC20 reward balance:", initialErc20Balance);

        // User1 claims rewards without unstaking
        vm.prank(user1);
        stakingVault.claimRewards(0);

        // Capture final balances after claiming rewards
        uint256 finalEthBalance = user1.balance;
        uint256 finalErc20Balance = rewardToken1.balanceOf(user1);
        console.log("Final ETH balance:", finalEthBalance);
        console.log("Final ERC20 reward balance:", finalErc20Balance);

        // Assertions to verify rewards are received
        assertGt(finalEthBalance, initialEthBalance, "User1 should have received ETH rewards");
        assertGt(finalErc20Balance, initialErc20Balance, "User1 should have received ERC20 rewards");
    }

    /**
     * @dev Test transferring a stake from one user to another.
     */
    function test_TransferStake() public {
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 90 days;

        // User1 buys staking tokens and stakes
        buyStakingTokens(user1, 1 ether);

        // User1 stakes staking tokens
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Add ETH rewards to the staking vault
        vm.deal(address(stakingVault), 1 ether);

        // Warp time to accumulate some rewards
        vm.warp(block.timestamp + 30 days);

        // Authorize this contract as a marketplace
        vm.prank(owner);
        stakingVault.setMarketplaceAuthorization(address(this), true);

        // Transfer stake from user1 to user2
        uint256 initialUser1Erc20 = rewardToken1.balanceOf(user1);
        uint256 initialUser2Erc20 = rewardToken1.balanceOf(user2);

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
            uint256 ethRewardDebt2
        ) = stakingVault.userStakes(user2, 0);
        assertEq(amount2, stakeAmount, "Transferred stake amount mismatch");
        assertEq(duration2, lockDuration, "Transferred stake lock duration mismatch");
        assertEq(shares2, stakeAmount, "Transferred stake shares mismatch");
        // ethRewardDebt2 should be updated appropriately; skipping exact value assertion

        // Check that pending rewards were transferred to user1
        uint256 finalUser1Erc20 = rewardToken1.balanceOf(user1);
        uint256 finalUser2Erc20 = rewardToken1.balanceOf(user2);

        assertGt(
            finalUser1Erc20,
            initialUser1Erc20,
            "User1 should have received pending ERC20 rewards upon stake transfer"
        );
        assertEq(
            finalUser2Erc20,
            initialUser2Erc20,
            "User2 should not have received ERC20 rewards upon stake transfer"
        );
    }

    /**
     * @dev Test staking and unstaking with multiple users and verifying rewards.
     */
    function test_MultipleUsersStakingAndRewards() public {
        // 1. Buy staking tokens for users
        buyStakingTokens(user1, 5 ether);
        buyStakingTokens(user2, 5 ether);
        buyStakingTokens(user3, 5 ether);

        // 2. Stake different amounts for different durations
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), 1000 * 1e18);
        stakingVault.stake(100 * 1e18, 30 days);
        stakingVault.stake(200 * 1e18, 60 days);
        vm.stopPrank();

        vm.startPrank(user2);
        stakingToken.approve(address(stakingVault), 1000 * 1e18);
        stakingVault.stake(300 * 1e18, 90 days);
        vm.stopPrank();

        vm.startPrank(user3);
        stakingToken.approve(address(stakingVault), 1000 * 1e18);
        stakingVault.stake(400 * 1e18, 180 days);
        vm.stopPrank();

        // 3. Owner deposits additional ERC20 rewards
        uint256 additionalErc20RewardAmount = 2000 * 1e18;
        rewardToken1.transfer(address(stakingVault), additionalErc20RewardAmount);

        // 4. Add ETH rewards to the staking vault
        vm.deal(address(stakingVault), 10 ether);

        // 5. Warp time to after all lock periods
        vm.warp(block.timestamp + 180 days);

        // 6. Update rewards (if applicable)
        stakingVault.updateRewards();

        // 7. Calculate total pending rewards
        uint256 totalPendingEthRewards = 0;
        uint256 totalPendingErc20Rewards = 0;

        // 7.a. Loop through user1's stakes
        for (uint256 i = 0; i < 2; i++) {
            (uint256 ethPending, uint256[] memory erc20Pending) =
                stakingVault.pendingRewards(user1, i);
            totalPendingEthRewards += ethPending;

            // Assuming only one ERC20 reward token is active
            if (erc20Pending.length > 0) {
                totalPendingErc20Rewards += erc20Pending[0];
            }
        }

        // 7.b. Add user2's stake rewards
        (uint256 eth2, uint256[] memory erc202) = stakingVault.pendingRewards(user2, 0);
        totalPendingEthRewards += eth2;
        if (erc202.length > 0) {
            totalPendingErc20Rewards += erc202[0];
        }

        // 7.c. Add user3's stake rewards
        (uint256 eth3, uint256[] memory erc203) = stakingVault.pendingRewards(user3, 0);
        totalPendingEthRewards += eth3;
        if (erc203.length > 0) {
            totalPendingErc20Rewards += erc203[0];
        }

        // 8. Log pending rewards for verification
        console.log("Total pending ETH rewards:", totalPendingEthRewards);
        console.log("Total pending ERC20 rewards:", totalPendingErc20Rewards);
        console.log(
            "Actual rewards in contract:",
            address(stakingVault).balance + rewardToken1.balanceOf(address(stakingVault))
        );

        // 9. Ensure total pending rewards don't exceed actual rewards
        assertLe(
            totalPendingEthRewards,
            10 ether,
            "Total pending ETH rewards exceed actual ETH in contract"
        );
        assertLe(
            totalPendingErc20Rewards,
            2000 * 1e18,
            "Total pending ERC20 rewards exceed actual ERC20 in contract"
        );

        // 10. Claim rewards for all users
        uint256 totalClaimedEthRewards = 0;
        uint256 totalClaimedErc20Rewards = 0;

        // 10.a. User1 claims rewards for both stakes
        vm.startPrank(user1);
        for (uint256 i = 0; i < 2; i++) {
            uint256 initialEthBalance = user1.balance;
            uint256 initialErc20Balance = rewardToken1.balanceOf(user1);
            stakingVault.claimRewards(i);
            totalClaimedEthRewards += user1.balance - initialEthBalance;
            totalClaimedErc20Rewards += rewardToken1.balanceOf(user1) - initialErc20Balance;
        }
        vm.stopPrank();

        // 10.b. User2 claims rewards for their stake
        vm.prank(user2);
        uint256 initialEthBalance2 = user2.balance;
        uint256 initialErc20Balance2 = rewardToken1.balanceOf(user2);
        stakingVault.claimRewards(0);
        totalClaimedEthRewards += user2.balance - initialEthBalance2;
        totalClaimedErc20Rewards += rewardToken1.balanceOf(user2) - initialErc20Balance2;

        // 10.c. User3 claims rewards for their stake
        vm.prank(user3);
        uint256 initialEthBalance3 = user3.balance;
        uint256 initialErc20Balance3 = rewardToken1.balanceOf(user3);
        stakingVault.claimRewards(0);
        totalClaimedEthRewards += user3.balance - initialEthBalance3;
        totalClaimedErc20Rewards += rewardToken1.balanceOf(user3) - initialErc20Balance3;

        // 11. Log claimed rewards for verification
        console.log("Total claimed ETH rewards:", totalClaimedEthRewards);
        console.log("Total claimed ERC20 rewards:", totalClaimedErc20Rewards);
        console.log("Remaining ETH in contract:", address(stakingVault).balance);
        console.log("Remaining ERC20 in contract:", rewardToken1.balanceOf(address(stakingVault)));

        // 12. Ensure all rewards are accounted for
        assertEq(
            totalClaimedEthRewards + address(stakingVault).balance,
            10 ether,
            "Total ETH rewards accounted for"
        );
        assertEq(
            totalClaimedErc20Rewards + rewardToken1.balanceOf(address(stakingVault)),
            2000 * 1e18,
            "Total ERC20 rewards accounted for"
        );

        // 13. After claiming rewards, verify that pending rewards are zero or very small
        (uint256 user1EthPending0, uint256[] memory user1Erc20Pending0) =
            stakingVault.pendingRewards(user1, 0);
        (uint256 user1EthPending1, uint256[] memory user1Erc20Pending1) =
            stakingVault.pendingRewards(user1, 1);
        uint256 totalUser1EthPending = user1EthPending0 + user1EthPending1;
        uint256 totalUser1Erc20Pending = 0;
        if (user1Erc20Pending0.length > 0) {
            totalUser1Erc20Pending += user1Erc20Pending0[0];
        }
        if (user1Erc20Pending1.length > 0) {
            totalUser1Erc20Pending += user1Erc20Pending1[0];
        }

        (uint256 user2EthPending, uint256[] memory user2Erc20Pending) =
            stakingVault.pendingRewards(user2, 0);
        (uint256 user3EthPending, uint256[] memory user3Erc20Pending) =
            stakingVault.pendingRewards(user3, 0);

        uint256 totalUser2EthPending = user2EthPending;
        uint256 totalUser2Erc20Pending = 0;
        if (user2Erc20Pending.length > 0) {
            totalUser2Erc20Pending += user2Erc20Pending[0];
        }

        uint256 totalUser3EthPending = user3EthPending;
        uint256 totalUser3Erc20Pending = 0;
        if (user3Erc20Pending.length > 0) {
            totalUser3Erc20Pending += user3Erc20Pending[0];
        }

        // Assert that pending rewards are zero or very small
        assertLe(totalUser1EthPending, 1, "User1 should have no pending ETH rewards");
        assertLe(totalUser1Erc20Pending, 1, "User1 should have no pending ERC20 rewards");
        assertLe(totalUser2EthPending, 1, "User2 should have no pending ETH rewards");
        assertLe(totalUser2Erc20Pending, 1, "User2 should have no pending ERC20 rewards");
        assertLe(totalUser3EthPending, 1, "User3 should have no pending ETH rewards");
        assertLe(totalUser3Erc20Pending, 1, "User3 should have no pending ERC20 rewards");
    }

    /**
     * @dev Test that only the owner can add reward tokens.
     */
    function test_AddRewardTokenByOwner() public {
        // Deploy a new reward token
        ERC20Mock newRewardToken = new ERC20Mock();

        // Owner adds a new reward token
        stakingVault.addERC20Reward(address(newRewardToken));

        // Check that the reward token is added
        assertEq(
            stakingVault.rewardTokenList(2),
            address(newRewardToken),
            "RewardToken2 not added as reward token"
        );
        (, uint256 accRewardPerShare, uint256 totalRewards, bool exists) =
            stakingVault.rewardTokens(address(newRewardToken));
        assertTrue(exists, "RewardToken2 should exist in rewardTokens mapping");
        assertEq(accRewardPerShare, 0, "Initial accRewardPerShare for RewardToken2 should be 0");
        assertEq(totalRewards, 0, "Initial totalRewards for RewardToken2 should be 0");
    }

    /**
     * @dev Test that non-owners cannot add reward tokens.
     */
    function test_AddRewardTokenByNonOwner() public {
        // Deploy a new reward token
        ERC20Mock newRewardToken = new ERC20Mock();

        // User1 attempts to add a new reward token
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        stakingVault.addERC20Reward(address(newRewardToken));
    }

    /**
     * @dev Test removing a reward token by the owner.
     */
    function test_RemoveRewardToken() public {
        // Deploy and add a new reward token
        ERC20Mock newRewardToken = new ERC20Mock();
        stakingVault.addERC20Reward(address(newRewardToken));

        // Owner removes the new reward token
        stakingVault.removeERC20Reward(address(newRewardToken));

        // Verify the reward token is removed
        (,,, bool exists) = stakingVault.rewardTokens(address(newRewardToken));
        assertFalse(exists, "RewardToken4 should have been removed");

        // Verify that rewardTokenList no longer contains the removed token
        bool found = false;

        // Retrieve the length using the new getter function
        uint256 rewardTokenListLength = stakingVault.getRewardTokenListLength();

        // Iterate over the rewardTokenList using the retrieved length
        for (uint256 i = 0; i < rewardTokenListLength; i++) {
            // Access each element using the autogenerated getter with the index
            address token = stakingVault.rewardTokenList(i);
            if (token == address(newRewardToken)) {
                found = true;
                break;
            }
        }

        // Assert that the token is not found
        require(!found, "New reward token still exists in the list.");
    }

    /**
     * @dev Test that non-owners cannot remove reward tokens.
     */
    function test_RemoveRewardTokenByNonOwner() public {
        // User1 attempts to remove a reward token
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        stakingVault.removeERC20Reward(address(rewardToken1));
    }

    /**
     * @dev Test staking and claiming rewards at different times for multiple users.
     */
    function test_MultipleUsersStakingAndClaimingRewardsAtDifferentTimes() public {
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 30 days;

        // User1 buys staking tokens and stakes
        buyStakingTokens(user1, 1 ether);

        // Owner deposits ERC20 rewards
        uint256 erc20RewardAmount = 1000 * 1e18;
        rewardToken1.transfer(address(stakingVault), erc20RewardAmount);

        // User1 stakes staking tokens
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Warp time by 10 days
        vm.warp(block.timestamp + 10 days);

        // User2 buys staking tokens and stakes
        buyStakingTokens(user2, 2 ether);

        vm.startPrank(user2);
        stakingToken.approve(address(stakingVault), 200 * 1e18);
        stakingVault.stake(200 * 1e18, 60 days);
        vm.stopPrank();

        // Warp time by 20 more days (total 30 days from start)
        vm.warp(block.timestamp + 20 days);

        // User1 claims rewards after 30 days
        vm.startPrank(user1);
        uint256 initialEthBalance1 = user1.balance;
        uint256 initialErc20Balance1 = rewardToken1.balanceOf(user1);
        stakingVault.claimRewards(0);
        uint256 finalEthBalance1 = user1.balance;
        uint256 finalErc20Balance1 = rewardToken1.balanceOf(user1);
        vm.stopPrank();

        console.log("User1 ETH rewards claimed:", finalEthBalance1 - initialEthBalance1);
        console.log("User1 ERC20 rewards claimed:", finalErc20Balance1 - initialErc20Balance1);

        // Warp time by 30 more days (total 60 days from start)
        vm.warp(block.timestamp + 30 days);

        // User2 claims rewards after 60 days
        vm.prank(user2);
        uint256 initialEthBalance2 = user2.balance;
        uint256 initialErc20Balance2 = rewardToken1.balanceOf(user2);
        stakingVault.claimRewards(0);
        uint256 finalEthBalance2 = user2.balance;
        uint256 finalErc20Balance2 = rewardToken1.balanceOf(user2);

        console.log("User2 ETH rewards claimed:", finalEthBalance2 - initialEthBalance2);
        console.log("User2 ERC20 rewards claimed:", finalErc20Balance2 - initialErc20Balance2);

        // Assertions to ensure rewards are received
        assertGt(finalEthBalance1, initialEthBalance1, "User1 should have received ETH rewards");
        assertGt(
            finalErc20Balance1, initialErc20Balance1, "User1 should have received ERC20 rewards"
        );
        assertGt(finalEthBalance2, initialEthBalance2, "User2 should have received ETH rewards");
        assertGt(
            finalErc20Balance2, initialErc20Balance2, "User2 should have received ERC20 rewards"
        );
    }

    /**
     * @dev Test that no additional rewards are accumulated after the timelock expiration.
     */
    function test_NoRewardsAfterTimelockExpiration() public {
        // User1 buys staking tokens
        buyStakingTokens(user1, 1 ether);

        // User1 stakes staking tokens for 30 days
        uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 30 days;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Warp time by 29 days (just before expiration)
        vm.warp(block.timestamp + 29 days);

        // Check pending rewards just before expiration
        (uint256 ethPendingBeforeExtension, uint256[] memory erc20PendingBeforeExtension) =
            stakingVault.pendingRewards(user1, 0);
        console.log("Pending ETH rewards before expiration:", ethPendingBeforeExtension);
        if (erc20PendingBeforeExtension.length > 0) {
            console.log("Pending ERC20 rewards before expiration:", erc20PendingBeforeExtension[0]);
        } else {
            console.log("No ERC20 pending rewards before expiration");
        }

        // Warp time by 2 more days (1 day after expiration)
        vm.warp(block.timestamp + 2 days);

        // Check pending rewards after expiration
        (uint256 ethPendingAfterExtension, uint256[] memory erc20PendingAfterExtension) =
            stakingVault.pendingRewards(user1, 0);
        console.log("Pending ETH rewards after expiration:", ethPendingAfterExtension);
        if (erc20PendingAfterExtension.length > 0) {
            console.log("Pending ERC20 rewards after expiration:", erc20PendingAfterExtension[0]);
        } else {
            console.log("No ERC20 pending rewards after expiration");
        }

        // Assert that no additional rewards were accumulated after expiration
        assertEq(
            ethPendingAfterExtension,
            ethPendingBeforeExtension,
            "ETH rewards should not change after expiration"
        );

        if (erc20PendingBeforeExtension.length > 0 && erc20PendingAfterExtension.length > 0) {
            assertEq(
                erc20PendingAfterExtension[0],
                erc20PendingBeforeExtension[0],
                "ERC20 rewards should not change after expiration"
            );
        } else {
            // If no ERC20 pending rewards, ensure the array lengths are consistent
            assertEq(
                erc20PendingAfterExtension.length,
                erc20PendingBeforeExtension.length,
                "ERC20 rewards array length should remain consistent after expiration"
            );
        }
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

        // Owner deposits ERC20 rewards
        uint256 erc20RewardAmount = 1000 * 1e18;
        rewardToken1.transfer(address(stakingVault), erc20RewardAmount);

        // User1 stakes staking tokens
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), initialStakeAmount);
        stakingVault.stake(initialStakeAmount, initialLockDuration);
        vm.stopPrank();

        console.log("Initial timestamp:", block.timestamp);
        console.log("Initial total shares:", stakingVault.totalShares());

        // Warp time by 15 days
        vm.warp(block.timestamp + 15 days);

        // Add ETH rewards over 15 days
        for (uint256 i = 0; i < 15; i++) {
            vm.warp(block.timestamp + 1 days);
            uint256 dailyFees = 0.1 ether * (1 + i % 5); // Varying daily fees

            // Deal ETH to the contract to simulate fees
            vm.deal(address(this), dailyFees);
            (bool success,) = address(stakingVault).call{value: dailyFees}("");
            require(success, "ETH transfer failed");
        }

        console.log("Timestamp after 15 days:", block.timestamp);
        console.log("Total shares before extension:", stakingVault.totalShares());

        // Check pending rewards before extension
        (uint256 ethPendingBeforeExtension, uint256[] memory erc20PendingBeforeExtension) =
            stakingVault.pendingRewards(user1, 0);
        console.log("Pending ETH rewards before extension:", ethPendingBeforeExtension);
        if (erc20PendingBeforeExtension.length > 0) {
            console.log("Pending ERC20 rewards before extension:", erc20PendingBeforeExtension[0]);
        } else {
            console.log("No ERC20 pending rewards before extension");
        }

        // Extend the stake
        vm.prank(user1);
        stakingVault.extendStake(0, extensionDuration);

        // Check pending rewards immediately after extension
        (uint256 ethPendingAfterExtension, uint256[] memory erc20PendingAfterExtension) =
            stakingVault.pendingRewards(user1, 0);
        console.log("Pending ETH rewards after extension:", ethPendingAfterExtension);
        if (erc20PendingAfterExtension.length > 0) {
            console.log("Pending ERC20 rewards after extension:", erc20PendingAfterExtension[0]);
        } else {
            console.log("No ERC20 pending rewards after extension");
        }
        console.log("Total shares after extension:", stakingVault.totalShares());

        // Ensure rewards didn't change due to extension
        assertEq(
            ethPendingBeforeExtension,
            ethPendingAfterExtension,
            "ETH rewards should not change immediately after extension"
        );
        if (erc20PendingBeforeExtension.length > 0 && erc20PendingAfterExtension.length > 0) {
            assertEq(
                erc20PendingBeforeExtension[0],
                erc20PendingAfterExtension[0],
                "ERC20 rewards should not change immediately after extension"
            );
        } else {
            // If no ERC20 pending rewards, ensure the array lengths are consistent
            assertEq(
                erc20PendingAfterExtension.length,
                erc20PendingBeforeExtension.length,
                "ERC20 rewards array length should remain consistent after extension"
            );
        }

        // Warp time by 75 more days (total 90 days from start)
        vm.warp(block.timestamp + 75 days);

        // Add more ETH rewards over the next 75 days
        for (uint256 i = 0; i < 75; i++) {
            vm.warp(block.timestamp + 1 days);
            uint256 dailyFees = 0.05 ether * (1 + i % 7); // Varying daily fees

            // Deal ETH to the contract to simulate fees
            vm.deal(address(this), dailyFees);
            (bool success,) = address(stakingVault).call{value: dailyFees}("");
            require(success, "ETH transfer failed");
        }

        console.log("Final timestamp:", block.timestamp);
        console.log("Total shares after extension:", stakingVault.totalShares());

        // Check final pending rewards
        (uint256 finalPendingEthRewards, uint256[] memory finalPendingErc20Rewards) =
            stakingVault.pendingRewards(user1, 0);
        console.log("Final pending ETH rewards:", finalPendingEthRewards);
        if (finalPendingErc20Rewards.length > 0) {
            console.log("Final pending ERC20 rewards:", finalPendingErc20Rewards[0]);
        } else {
            console.log("No ERC20 pending rewards after extension");
        }

        // Claim rewards and check received amount
        uint256 initialEthBalance = user1.balance;
        uint256 initialErc20Balance = rewardToken1.balanceOf(user1);
        vm.prank(user1);
        stakingVault.claimRewards(0);
        uint256 claimedEthRewards = user1.balance - initialEthBalance;
        uint256 claimedErc20Rewards = rewardToken1.balanceOf(user1) - initialErc20Balance;

        console.log("Claimed ETH rewards:", claimedEthRewards);
        console.log("Claimed ERC20 rewards:", claimedErc20Rewards);

        // Verify pending rewards are now zero or very small
        (uint256 pendingRewardsAfterClaimEth, uint256[] memory pendingRewardsAfterClaimErc20) =
            stakingVault.pendingRewards(user1, 0);
        console.log("Pending ETH rewards after claim:", pendingRewardsAfterClaimEth);
        if (pendingRewardsAfterClaimErc20.length > 0) {
            console.log("Pending ERC20 rewards after claim:", pendingRewardsAfterClaimErc20[0]);
        } else {
            console.log("No ERC20 pending rewards after claim");
        }
        assertLe(
            pendingRewardsAfterClaimEth,
            1e14,
            "Pending ETH rewards after claim should be very small"
        );
        if (pendingRewardsAfterClaimErc20.length > 0) {
            assertLe(
                pendingRewardsAfterClaimErc20[0],
                1e14,
                "Pending ERC20 rewards after claim should be very small"
            );
        }

        // Verify total rewards distributed match total fees
        uint256 remainingEth = address(stakingVault).balance;
        uint256 remainingErc20 = rewardToken1.balanceOf(address(stakingVault));
        console.log("Remaining ETH in staking vault:", remainingEth);
        console.log("Remaining ERC20 in staking vault:", remainingErc20);

        assertApproxEqRel(
            claimedEthRewards + remainingEth,
            1 ether + 15 * 0.1 ether + 75 * 0.05 ether, // Total ETH fees sent: 1 + 1.5 + 3.75 = 6.25 ether
            1e16,
            "Total ETH distributed should match total fees sent"
        );
        assertApproxEqRel(
            claimedErc20Rewards + remainingErc20,
            1000 * 1e18,
            1e14,
            "Total ERC20 distributed should match deposited rewards"
        );
    }

    /**
     * @dev Test ERC20 rewards distribution to a single user.
     */
    function test_Erc20RewardsDistribution() public {
        uint256 stakeAmount = 500 * 1e18;
        uint256 lockDuration = 90 days;
        uint256 erc20RewardAmount = 5000 * 1e18;

        // User1 buys staking tokens
        buyStakingTokens(user1, 5 ether);

        // Owner deposits ERC20 rewards
        rewardToken1.transfer(address(stakingVault), erc20RewardAmount);

        // User1 stakes staking tokens
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Warp time to after lock period
        vm.warp(block.timestamp + lockDuration);

        // User1 unstakes and claims rewards
        vm.prank(user1);
        stakingVault.unstake(0);

        // Calculate expected ERC20 rewards
        // Since only user1 has staked, they should receive all ERC20 rewards
        uint256 user1Erc20Balance = rewardToken1.balanceOf(user1);
        assertEq(user1Erc20Balance, erc20RewardAmount, "User1 should receive all ERC20 rewards");

        // Check ETH rewards
        uint256 user1EthBalance = user1.balance;
        assertEq(user1EthBalance, 0, "User1 should have no ETH rewards since none were added");
    }

    /**
     * @dev Test ERC20 rewards distribution without ETH rewards.
     */
    function test_Erc20RewardsWithoutEthRewards() public {
        uint256 stakeAmount = 300 * 1e18;
        uint256 lockDuration = 60 days;
        uint256 erc20RewardAmount = 3000 * 1e18;

        // User2 buys staking tokens and stakes
        buyStakingTokens(user2, 3 ether);

        // Owner deposits ERC20 rewards
        rewardToken1.transfer(address(stakingVault), erc20RewardAmount);

        // User2 stakes staking tokens
        vm.startPrank(user2);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Warp time to accumulate rewards
        vm.warp(block.timestamp + lockDuration);

        // User2 unstakes and claims rewards
        vm.prank(user2);
        stakingVault.unstake(0);

        // Check ERC20 rewards
        uint256 user2Erc20Balance = rewardToken1.balanceOf(user2);
        assertEq(user2Erc20Balance, erc20RewardAmount, "User2 should receive all ERC20 rewards");

        // Check ETH rewards (should be zero)
        uint256 user2EthBalance = user2.balance;
        assertEq(user2EthBalance, 0, "User2 should receive no ETH rewards");
    }

    /**
     * @dev Test handling multiple reward tokens.
     */
    function test_MultipleRewardTokens() public {
        // Deploy and add a second reward token
        ERC20Mock newRewardToken = new ERC20Mock();
        stakingVault.addERC20Reward(address(newRewardToken));
        rewardToken2 = newRewardToken;

        // Mint RewardToken2 to this contract
        rewardToken2.mint(address(this), 3000 * 1e18);

        // User1 buys staking tokens and stakes
        buyStakingTokens(user1, 2 ether);
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), 200 * 1e18);
        stakingVault.stake(200 * 1e18, 60 days);
        vm.stopPrank();

        // Add ETH rewards
        vm.deal(address(stakingVault), 2 ether);

        // Transfer rewards for both tokens
        rewardToken1.approve(address(stakingVault), 500 * 1e18);
        stakingVault.depositERC20Rewards(address(rewardToken1), 500 * 1e18);

        rewardToken2.approve(address(stakingVault), 3000 * 1e18);
        stakingVault.depositERC20Rewards(address(rewardToken2), 3000 * 1e18);

        // Warp time to after lock period
        vm.warp(block.timestamp + 60 days);

        // User1 unstakes and claims rewards
        vm.prank(user1);
        stakingVault.unstake(0);

        // Check ETH rewards
        uint256 user1EthBalance = user1.balance;
        assertEq(user1EthBalance, 2 ether, "User1 should receive all ETH rewards");

        // Check ERC20 rewards from both tokens
        uint256 user1Erc20Balance1 = rewardToken1.balanceOf(user1);
        uint256 user1Erc20Balance2 = rewardToken2.balanceOf(user1);
        assertEq(user1Erc20Balance1, 500 * 1e18, "User1 should receive 500 RewardToken1");
        assertEq(user1Erc20Balance2, 300 * 1e18, "User1 should receive 300 RewardToken2");
    }

    /**
     * @dev Test that non-owners cannot add reward tokens.
     */
    function test_Erc20RewardDepositByNonOwner() public {
        // Deploy a new reward token
        ERC20Mock newRewardToken = new ERC20Mock();

        // User3 attempts to add a new reward token
        vm.prank(user3);
        vm.expectRevert("Ownable: caller is not the owner");
        stakingVault.addERC20Reward(address(newRewardToken));
    }

    /**
     * @dev Test claiming rewards after unstaking.
     */
    function test_Erc20RewardClaims() public {
        // uint256 stakeAmount = 100 * 1e18;
        uint256 lockDuration = 30 days;
        uint256 erc20RewardAmount = 1000 * 1e18;

        // User1 buys staking tokens
        buyStakingTokens(user1, 1 ether);

        uint256 stakeAmount = stakingToken.balanceOf(user1);

        // Get contract total shares before
        uint256 totalSharesBefore = stakingVault.totalShares();
        console.log("Total shares before:", totalSharesBefore);

        // Get reward token data before
        (, uint256 accRewardPerShareBefore,,) = stakingVault.rewardTokens(address(rewardToken1));
        console.log("Acc reward per share before:", accRewardPerShareBefore);

        // Get acc eth reward per share before
        uint256 accEthRewardPerShareBefore = stakingVault.accEthRewardPerShare();
        console.log("Acc ETH reward per share before:", accEthRewardPerShareBefore);

        // User1 stakes staking tokens
        vm.startPrank(user1);
        stakingToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, lockDuration);
        vm.stopPrank();

        // Get contract total shares after
        uint256 totalSharesAfter = stakingVault.totalShares();
        console.log("Total shares after staking:", totalSharesAfter);

        // Get reward token data after
        (, uint256 accRewardPerShareAfter,,) = stakingVault.rewardTokens(address(rewardToken1));
        console.log("Acc reward per share after staking:", accRewardPerShareAfter);

        // Get acc eth reward per share after
        uint256 accEthRewardPerShareAfter = stakingVault.accEthRewardPerShare();
        console.log("Acc ETH reward per share after staking:", accEthRewardPerShareAfter);

        // Get User1 shares
        (,,, uint256 shares,) = stakingVault.userStakes(user1, 0);
        console.log("User1 shares staking:", shares);

        // deposit ERC20 rewards after the user stakes
        rewardToken1.approve(address(stakingVault), erc20RewardAmount);
        stakingVault.depositERC20Rewards(address(rewardToken1), erc20RewardAmount);

        // get user1 pending rewards
        (uint256 pendingEthRewards, uint256[] memory pendingErc20Rewards) =
            stakingVault.pendingRewards(user1, 0);

        console.log("User1 pending ETH rewards:", pendingEthRewards);
        console.log("User1 pending unai rewards:", pendingErc20Rewards[0]);
        console.log("User1 pending ERC20 rewards:", pendingErc20Rewards[1]);

        //get contract balances for eth and erc20s
        uint256 contractEthBalance = address(stakingVault).balance;
        uint256 contractErc20Balance = rewardToken1.balanceOf(address(stakingVault));
        uint256 contractUNAIBalance = stakingToken.balanceOf(address(stakingVault));
        //subtract total stakked from contract balance
        contractUNAIBalance = contractUNAIBalance - stakingVault.totalStaked();

        console.log("Contract ETH balance:", contractEthBalance);
        console.log("Contract ERC20 balance:", contractErc20Balance);
        console.log("Contract UNAI balance:", contractUNAIBalance);

        // Warp time to after lock period
        vm.warp(block.timestamp + lockDuration);

        // User1 unstakes and claims rewards
        vm.prank(user1);
        stakingVault.unstake(0);

        // Check ERC20 rewards
        uint256 user1Erc20Balance = rewardToken1.balanceOf(user1);
        assertEq(user1Erc20Balance, erc20RewardAmount, "User1 should receive all ERC20 rewards");

        // Check ETH rewards (should be zero)
        uint256 user1EthBalance = user1.balance;
        assertEq(user1EthBalance, 0, "User1 should receive no ETH rewards");

        // Check pending rewards after unstaking
        (pendingEthRewards, pendingErc20Rewards) = stakingVault.pendingRewards(user1, 0);
        assertEq(pendingEthRewards, 0, "User1 should have no pending ETH rewards after unstaking");
        assertEq(
            pendingErc20Rewards.length,
            0,
            "User1 should have no pending ERC20 rewards after unstaking"
        );
    }
}
