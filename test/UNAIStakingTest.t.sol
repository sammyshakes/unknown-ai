// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {StakingVault, IERC20} from "../src/UNAIStaking.sol";
import {Contract, IDexRouter} from "../src/UNAI.sol";

contract UNAIStakingTest is Test {
    StakingVault public stakingVault;
    Contract public unaiToken; // This is the UNAI token used for staking and rewards

    // dex router address
    // address public router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public router = address(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008); // Sepolia

    IDexRouter dexRouter = IDexRouter(router);

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    function setUp() public {
        unaiToken = new Contract();
        stakingVault = new StakingVault(IERC20(address(unaiToken)));
        unaiToken.setStakingContract(address(stakingVault));

        //get total supply
        assertEq(unaiToken.totalSupply(), 10 * 1e6 * 1e18);

        //check balance of owner
        assertEq(unaiToken.balanceOf(owner), unaiToken.totalSupply());

        // Provide liquidity to the pool
        uint256 ethAmount = 10 ether;
        uint256 tokenAmount = 10_000_000 * 1e18;

        // Deal some ETH to the owner
        vm.deal(owner, ethAmount);

        unaiToken.approve(address(dexRouter), tokenAmount);

        dexRouter.addLiquidityETH{value: 1 ether}(
            address(unaiToken), tokenAmount, 0, 0, owner, block.timestamp
        );

        stakingVault.addPool(180 days, 10);

        unaiToken.enableTrading(1);

        //remove limits
        unaiToken.removeLimits();

        // roll the block to the future
        vm.roll(block.number + 2);
    }

    function buyTokens(address buyer, uint256 ethAmount) private {
        // Deal some ETH to the buyer
        vm.deal(buyer, ethAmount);

        address[] memory path = new address[](2);

        // Buy tokens from the liquidity pool
        vm.startPrank(buyer);
        path[0] = dexRouter.WETH();
        path[1] = address(unaiToken);

        dexRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            0, // accept any amount of tokens
            path,
            buyer,
            block.timestamp
        );
        vm.stopPrank();
    }

    function test_ClaimRewards() public {
        uint256 poolId = 0;

        // Add a pool to the staking vault
        vm.prank(owner);
        stakingVault.addPool(30 days, 1);

        // User1 buys tokens
        buyTokens(user1, 1 ether);

        // Stake tokens
        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), 100 * 1e18);
        stakingVault.stake(poolId, 100 * 1e18);
        vm.stopPrank();

        // Distribute rewards to the pool
        vm.prank(owner);
        stakingVault.distributeRewards{value: 1 ether}();

        // Warp to simulate passage of time
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 10);

        // Check initial ETH balance
        uint256 initialEthBalance = address(user1).balance;
        console.log("Initial ETH balance:", initialEthBalance);

        // Claim rewards
        vm.startPrank(user1);
        stakingVault.claimRewards(poolId, 0);
        vm.stopPrank();

        // Check final ETH balance
        uint256 finalEthBalance = address(user1).balance;
        console.log("Final ETH balance:", finalEthBalance);

        // Ensure that the rewards were successfully transferred
        assertTrue(finalEthBalance > initialEthBalance, "User1 should have received ETH rewards");
    }

    function test_StakeAndUnstake() public {
        uint256 poolId = 0;

        // User1 buys tokens
        buyTokens(user1, 1 ether);

        console.log("User1 balance before staking:", unaiToken.balanceOf(user1));

        vm.startPrank(user1);
        unaiToken.approve(address(stakingVault), 100 * 1e18);
        stakingVault.stake(poolId, 100 * 1e18);
        vm.stopPrank();

        console.log("User1 balance after staking:", unaiToken.balanceOf(user1));

        (uint256 amount,, address stakeOwner,) = stakingVault.stakes(user1, poolId, 0);
        console.log("Staked amount:", amount);
        console.log("Stake owner:", stakeOwner);

        assertEq(amount, 100 * 1e18);
        assertEq(stakeOwner, user1);

        // Add rewards to the pool
        stakingVault.distributeRewards{value: 1 ether}();

        console.log("Rewards added to staking vault:", address(stakingVault).balance);

        // Warp time and roll blocks
        vm.warp(block.timestamp + 180 days);
        vm.roll(block.number + 10);

        uint256 initialEthBalance = user1.balance;
        console.log("User1 ETH balance before unstaking:", initialEthBalance);

        // Log pool information before unstaking
        (
            uint256 lockPeriod,
            uint256 accETHPerShare,
            uint256 totalStaked,
            uint256 lastRewardTime,
            uint256 lastRewardBalance,
            uint256 weight
        ) = stakingVault.pools(poolId);
        console.log("Pool lock period:", lockPeriod);
        console.log("Pool accETHPerShare:", accETHPerShare);
        console.log("Pool total staked:", totalStaked);
        console.log("Pool last reward time:", lastRewardTime);
        console.log("Pool last reward balance:", lastRewardBalance);
        console.log("Pool weight:", weight);

        vm.startPrank(user1);
        stakingVault.updatePool(poolId, false);
        (, accETHPerShare,,,,) = stakingVault.pools(poolId);

        console.log("Pool accETHPerShare after update:", accETHPerShare);
        uint256 pendingRewards = stakingVault.pendingRewards(user1, poolId, 0);
        console.log("Pending rewards before unstaking:", pendingRewards);
        stakingVault.unstake(poolId, 0);
        vm.stopPrank();

        (amount,, stakeOwner,) = stakingVault.stakes(user1, poolId, 0);
        console.log("Staked amount after unstaking:", amount);
        console.log("Stake owner after unstaking:", stakeOwner);

        assertEq(amount, 0);
        assertEq(stakeOwner, address(0));

        // Check if user received ETH rewards
        uint256 finalEthBalance = user1.balance;
        assertGt(finalEthBalance, initialEthBalance, "User should have received ETH rewards");
        console.log("User1 ETH balance after unstaking:", finalEthBalance);
        console.log("ETH balance difference:", finalEthBalance - initialEthBalance);

        // Check if user received rewards
        uint256 userEthBalance = user1.balance;
        console.log("User1 ETH balance after unstaking:", userEthBalance);
    }

    // function test_StakeTransfer() public {
    //     uint256 poolId = 0;

    //     // Add a pool to the staking vault
    //     vm.prank(owner);
    //     stakingVault.addPool(30 days, 1);

    //     // User1 buys tokens
    //     buyTokens(user1, 1 ether);

    //     // Stake tokens
    //     vm.startPrank(user1);
    //     unaiToken.approve(address(stakingVault), 100 * 1e18);
    //     stakingVault.stake(poolId, 100 * 1e18);
    //     vm.stopPrank();

    //     stakingVault.distributeRewards{value: 1 ether}();

    //     // Warp time to accumulate rewards
    //     vm.warp(block.timestamp + 1 days);

    //     // Approve transfer of the stake
    //     vm.startPrank(user1);
    //     stakingVault.approveStakeTransfer(user2, poolId, 0);
    //     vm.stopPrank();

    //     // Transfer the stake
    //     vm.startPrank(user2);
    //     stakingVault.transferStake(user1, user2, poolId, 0);
    //     vm.stopPrank();

    //     // Check the new owner of the stake
    //     (,, address newOwner,) = stakingVault.stakes(user2, poolId, 0);
    //     assertEq(newOwner, user2);

    //     // Verify that the reward debt of the transferred stake is correct
    //     uint256 pendingRewardsUser2 = stakingVault.pendingRewards(user2, poolId, 0);
    //     assertTrue(pendingRewardsUser2 > 0, "User2 should have pending rewards after transfer");

    //     // Claim rewards for user2
    //     vm.startPrank(user2);
    //     stakingVault.claimRewards(poolId, 0);
    //     vm.stopPrank();

    //     // Ensure that the rewards were successfully transferred
    //     uint256 finalEthBalance = address(user2).balance;
    //     assertTrue(finalEthBalance > 0, "User2 should have received ETH rewards");
    // }

    function test_PeriodicBuysAndSellsWithRewards() public {
        uint256 poolId = 0;
        address[5] memory users =
            [address(0x1), address(0x2), address(0x3), address(0x4), address(0x5)];

        // Fund the staking contract with ETH for rewards
        vm.deal(address(stakingVault), 100 ether);

        // Users buy and sell tokens periodically
        for (uint256 i = 0; i < 1; i++) {
            for (uint256 j = 0; j < users.length; j++) {
                address user = users[j];

                // Multiple buys per user per iteration
                for (uint256 k = 0; k < 2; k++) {
                    // User buys tokens from the liquidity pool
                    buyTokens(user, 1 ether);

                    // Log user balance after buying tokens
                    console.log("Iteration:", i);
                    console.log("User:", user);
                    console.log("Balance UNAI after buy:", unaiToken.balanceOf(user) / 1e18);

                    // tokens for staking
                    uint256 tokensForStaking = unaiToken.tokensForStaking();
                    console.log("Tokens for staking", tokensForStaking / 1e18);
                }

                // User stakes tokens
                vm.startPrank(user);
                unaiToken.approve(address(stakingVault), 100 * 1e18);
                stakingVault.stake(poolId, 100 * 1e18);
                vm.stopPrank();

                // Log staking details
                console.log("Iteration:", i);
                console.log("User:", user);
                console.log("Staked 100 tokens");

                // Roll the block to simulate the passage of time
                vm.warp(block.timestamp + 1 days);
                vm.roll(block.number + 10);

                // Multiple sells per user per iteration
                for (uint256 k = 0; k < 1; k++) {
                    // User sells some tokens back to the liquidity pool
                    vm.startPrank(user);
                    address[] memory path = new address[](2);
                    path[0] = address(unaiToken);
                    path[1] = dexRouter.WETH();

                    unaiToken.approve(address(dexRouter), 100 * 1e18);
                    try dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
                        100 * 1e18,
                        0, // accept any amount of ETH
                        path,
                        user,
                        block.timestamp
                    ) {
                        console.log("User:", user);
                        console.log("Successfully swapped tokens for ETH");
                    } catch {
                        console.log("User:", user);
                        console.log("Failed to swap tokens for ETH");
                    }
                    vm.stopPrank();

                    // Log user balance after selling tokens
                    console.log("Iteration:", i);
                    console.log("User:", user);
                    console.log("Balance UNAI after sell:", unaiToken.balanceOf(user) / 1e18);
                }
            }
        }

        // Roll the block to simulate the passage of time
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 10);

        // Check rewards for each user
        for (uint256 j = 0; j < users.length; j++) {
            address user = users[j];

            vm.startPrank(user);
            uint256 initialBalance = user.balance; // Use ETH balance instead of token balance
            console.log("User:", user);
            console.log("Initial ETH balance before claiming rewards", initialBalance);

            // Calculate and log claimable rewards for the user
            uint256 pendingRewards = stakingVault.pendingRewards(user, poolId, 0);
            console.log("User:", user);
            console.log("Claimable rewards", pendingRewards);

            // Log the contract balance before claiming rewards
            console.log("Contract balance", address(stakingVault).balance);

            stakingVault.claimRewards(poolId, 0);
            uint256 finalBalance = user.balance; // Use ETH balance instead of token balance
            console.log("User:", user);
            console.log("Final ETH balance after claiming rewards", finalBalance);
            assert(finalBalance > initialBalance);
            vm.stopPrank();
        }
    }
}
