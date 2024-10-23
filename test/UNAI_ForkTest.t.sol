// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Contract, IDexRouter} from "../src/UNAI.sol";
import {StakingVault, IERC20} from "../src/UNAIStaking.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUNAI {
    function tokensForOperations() external view returns (uint256);
    function tokensForLiquidity() external view returns (uint256);
    function tokensForDev() external view returns (uint256);
    function tokensForBurn() external view returns (uint256);
    function tokensForStaking() external view returns (uint256);
    function setSwapStakingEnabled(bool _enabled) external;
    function forceSwapBack() external;
    function sellStakingRewardsFee() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function enableTrading(uint256 deadBlocks) external;
    function removeLimits() external;
    function buyTotalFees() external view returns (uint256);
    function sellTotalFees() external view returns (uint256);
    function swapTokensAtAmount() external view returns (uint256);
    function updateSwapTokensAtAmount(uint256 newAmount) external;
    function setStakingContract(address _stakingVault) external;
    function setDevAddress(address _devAddress) external;
    function updateBuyFees(
        uint256 _operationsFee,
        uint256 _liquidityFee,
        uint256 _devFee,
        uint256 _burnFee,
        uint256 _stakingRewardsFee
    ) external;
    function updateSellFees(
        uint256 _operationsFee,
        uint256 _liquidityFee,
        uint256 _devFee,
        uint256 _burnFee,
        uint256 _stakingRewardsFee
    ) external;
}

contract UNAIForkTest is Test {
    // Replace these with the actual deployed addresses on the forked network
    address constant UNAI_ADDRESS = 0x2A762B4587197119539ca675f7C8B214CF9EdA73; // mainnet address
    // address constant STAKING_VAULT_ADDRESS = address(0x0005); // Replace with actual address
    address constant DEX_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Replace with actual address

    IUNAI public unaiToken;
    StakingVault public stakingVault;
    IDexRouter public dexRouter;

    // Setup users
    address public owner = vm.envAddress("DEPLOYER_ADDRESS");
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    // Fork URL is set via foundry.toml; no need to set here unless overriding
    function setUp() public {
        // Connect to deployed contracts
        unaiToken = IUNAI(UNAI_ADDRESS);
        stakingVault = new StakingVault(address(unaiToken));
        dexRouter = IDexRouter(DEX_ROUTER_ADDRESS);

        // Optionally, impersonate the owner if required for certain actions
        vm.startPrank(owner);

        //set staking vault address
        unaiToken.setStakingContract(address(stakingVault));

        // Enable staking swap if not already enabled
        unaiToken.setSwapStakingEnabled(true);

        vm.stopPrank();
    }

    // Helper function to simulate token purchase
    function buyTokens(address buyer, uint256 ethAmount) private {
        // Deal some ETH to the buyer
        vm.deal(buyer, ethAmount);

        address[] memory path = new address[](2);
        path[0] = dexRouter.WETH();
        path[1] = UNAI_ADDRESS;

        vm.startPrank(buyer);
        dexRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            0, // accept any amount of tokens
            path,
            buyer,
            block.timestamp
        );
        vm.stopPrank();
    }

    // Helper function to simulate token sale
    function sellTokens(address seller, uint256 tokenAmount) private {
        vm.startPrank(seller);
        IERC20(UNAI_ADDRESS).approve(address(dexRouter), tokenAmount);

        address[] memory path = new address[](2);
        path[0] = UNAI_ADDRESS;
        path[1] = dexRouter.WETH();

        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            seller,
            block.timestamp
        );
        vm.stopPrank();
    }

    function test_Fork_BuyTokensForStakingAndDeposit() public {
        //disable staking swap
        vm.prank(owner);
        unaiToken.setSwapStakingEnabled(false);

        // Initial staking tokens
        uint256 initialContractBalance = IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS);
        emit log_named_uint("Initial contract token balance", initialContractBalance / 1e18);

        uint256 initialTokensForStaking = unaiToken.tokensForStaking();
        uint256 initialTokensForOperations = unaiToken.tokensForOperations();
        uint256 initialTokensForLiquidity = unaiToken.tokensForLiquidity();
        uint256 initialTokensForDev = unaiToken.tokensForDev();
        uint256 initialTokensForBurn = unaiToken.tokensForBurn();

        //sum tokensFor
        uint256 initialTokensForSum = initialTokensForOperations + initialTokensForLiquidity
            + initialTokensForDev + initialTokensForBurn + initialTokensForStaking;

        //console log contract variables
        console.log("tokensForOperations", initialTokensForOperations / 1e18);
        console.log("tokensForLiquidity", initialTokensForLiquidity / 1e18);
        console.log("tokensForDev", initialTokensForDev / 1e18);
        console.log("tokensForBurn", initialTokensForBurn / 1e18);
        console.log("tokensForStaking", initialTokensForStaking / 1e18);
        console.log("swapTokensAtAmount", unaiToken.swapTokensAtAmount() / 1e18);
        console.log("====================================");
        console.log("Initial tokensForSum", initialTokensForSum / 1e18);
        console.log("Initial contract token balance", initialContractBalance / 1e18);
        console.log("Stakingvault ETH balance", address(stakingVault).balance / 1e18);
        console.log("====================================");

        // Perform a buy to accumulate staking tokens
        uint256 buyEthAmount = 5 ether;
        buyTokens(user1, buyEthAmount);

        // get user1 balance
        uint256 user1Balance = IERC20(UNAI_ADDRESS).balanceOf(user1);
        // console.log("User1 balance", user1Balance / 1e18);

        // console contract variables
        console.log("tokensForOperations", unaiToken.tokensForOperations() / 1e18);
        console.log("tokensForLiquidity", unaiToken.tokensForLiquidity() / 1e18);
        console.log("tokensForDev", unaiToken.tokensForDev() / 1e18);
        console.log("tokensForBurn", unaiToken.tokensForBurn() / 1e18);
        console.log("tokensForStaking", unaiToken.tokensForStaking() / 1e18);
        console.log("swapTokensAtAmount", unaiToken.swapTokensAtAmount() / 1e18);
        console.log("====================================");
        console.log("Contract token balance", IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS) / 1e18);
        console.log("Stakingvault ETH balance", address(stakingVault).balance);

        uint256 totalTokensForSum = unaiToken.tokensForOperations() + unaiToken.tokensForLiquidity()
            + unaiToken.tokensForDev() + unaiToken.tokensForBurn() + unaiToken.tokensForStaking();
        console.log("Total tokensForSum", totalTokensForSum / 1e18);
        // uint256 amountToDeposit = totalTokensForSum - IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS);

        // //deposit an amount equal to tokensForStaking into unaiToken contract
        // vm.prank(user1);
        // IERC20(address(unaiToken)).transfer(address(unaiToken), amountToDeposit);

        // console.log("Depositing tokens into unaiToken contract", amountToDeposit / 1e18);

        // get contract balance
        uint256 contractBalance = IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS);
        console.log("Contract balance", contractBalance / 1e18);
        console.log("Stakingvault ETH balance", address(stakingVault).balance);

        vm.prank(owner);
        unaiToken.updateSwapTokensAtAmount(1000 ether);

        //set swap staking enabled
        vm.prank(owner);
        unaiToken.setSwapStakingEnabled(true);

        // perform a buy to accumulate staking tokens
        buyTokens(user2, 2 ether);
        buyTokens(user1, 2 ether);

        // get user2 balance
        uint256 user2Balance = IERC20(UNAI_ADDRESS).balanceOf(user2);
        console.log("User2 balance", user2Balance / 1e18);

        // console contract variables
        console.log("tokensForOperations", unaiToken.tokensForOperations() / 1e18);
        console.log("tokensForLiquidity", unaiToken.tokensForLiquidity() / 1e18);
        console.log("tokensForDev", unaiToken.tokensForDev() / 1e18);
        console.log("tokensForBurn", unaiToken.tokensForBurn() / 1e18);
        console.log("tokensForStaking", unaiToken.tokensForStaking() / 1e18);
        console.log("swapTokensAtAmount", unaiToken.swapTokensAtAmount() / 1e18);
        console.log("====================================");
        console.log("Contract token balance", IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS) / 1e18);

        console.log("Stakingvault ETH balance", address(stakingVault).balance);

        totalTokensForSum = unaiToken.tokensForOperations() + unaiToken.tokensForLiquidity()
            + unaiToken.tokensForDev() + unaiToken.tokensForBurn() + unaiToken.tokensForStaking();
        console.log("Total tokensForSum", totalTokensForSum / 1e18);
        console.log("====================================");

        buyTokens(user1, 10 ether);
        // console contract variables
        console.log("tokensForOperations", unaiToken.tokensForOperations() / 1e18);
        console.log("tokensForLiquidity", unaiToken.tokensForLiquidity() / 1e18);
        console.log("tokensForDev", unaiToken.tokensForDev() / 1e18);
        console.log("tokensForBurn", unaiToken.tokensForBurn() / 1e18);
        console.log("tokensForStaking", unaiToken.tokensForStaking() / 1e18);
        console.log("swapTokensAtAmount", unaiToken.swapTokensAtAmount() / 1e18);
        console.log("====================================");

        totalTokensForSum = unaiToken.tokensForOperations() + unaiToken.tokensForLiquidity()
            + unaiToken.tokensForDev() + unaiToken.tokensForBurn() + unaiToken.tokensForStaking();
        console.log("Total tokensForSum:", totalTokensForSum / 1e18);
        console.log("Contract token balance", IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS) / 1e18);
        console.log("Stakingvault ETH balance", address(stakingVault).balance);
        console.log("====================================");

        // get user1 balance
        user1Balance = IERC20(UNAI_ADDRESS).balanceOf(user1);
        // sellTokens(user1, user1Balance);
        buyTokens(user1, 5 ether);

        // console contract variables
        console.log("tokensForOperations", unaiToken.tokensForOperations() / 1e18);
        console.log("tokensForLiquidity", unaiToken.tokensForLiquidity() / 1e18);
        console.log("tokensForDev", unaiToken.tokensForDev() / 1e18);
        console.log("tokensForBurn", unaiToken.tokensForBurn() / 1e18);
        console.log("tokensForStaking", unaiToken.tokensForStaking() / 1e18);
        console.log("swapTokensAtAmount", unaiToken.swapTokensAtAmount() / 1e18);
        console.log("====================================");

        totalTokensForSum = unaiToken.tokensForOperations() + unaiToken.tokensForLiquidity()
            + unaiToken.tokensForDev() + unaiToken.tokensForBurn() + unaiToken.tokensForStaking();
        console.log("Total tokensForSum:", totalTokensForSum / 1e18);
        console.log("Contract token balance", IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS) / 1e18);
        console.log("Stakingvault ETH balance", address(stakingVault).balance);
        console.log("====================================");

        sellTokens(user1, user1Balance);

        // console contract variables
        console.log("tokensForOperations", unaiToken.tokensForOperations() / 1e18);
        console.log("tokensForLiquidity", unaiToken.tokensForLiquidity() / 1e18);
        console.log("tokensForDev", unaiToken.tokensForDev() / 1e18);
        console.log("tokensForBurn", unaiToken.tokensForBurn() / 1e18);
        console.log("tokensForStaking", unaiToken.tokensForStaking() / 1e18);
        console.log("swapTokensAtAmount", unaiToken.swapTokensAtAmount() / 1e18);
        console.log("====================================");

        totalTokensForSum = unaiToken.tokensForOperations() + unaiToken.tokensForLiquidity()
            + unaiToken.tokensForDev() + unaiToken.tokensForBurn() + unaiToken.tokensForStaking();
        console.log("Total tokensForSum:", totalTokensForSum / 1e18);
        console.log("Contract token balance", IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS) / 1e18);
        console.log("Stakingvault ETH balance", address(stakingVault).balance);
        console.log("====================================");

        buyTokens(user1, 5 ether);
        buyTokens(user2, 5 ether);

        // console contract variables
        console.log("tokensForOperations", unaiToken.tokensForOperations() / 1e18);
        console.log("tokensForLiquidity", unaiToken.tokensForLiquidity() / 1e18);
        console.log("tokensForDev", unaiToken.tokensForDev() / 1e18);
        console.log("tokensForBurn", unaiToken.tokensForBurn() / 1e18);
        console.log("tokensForStaking", unaiToken.tokensForStaking() / 1e18);
        console.log("swapTokensAtAmount", unaiToken.swapTokensAtAmount() / 1e18);
        console.log("====================================");

        totalTokensForSum = unaiToken.tokensForOperations() + unaiToken.tokensForLiquidity()
            + unaiToken.tokensForDev() + unaiToken.tokensForBurn() + unaiToken.tokensForStaking();
        console.log("Total tokensForSum:", totalTokensForSum / 1e18);
        console.log("Contract token balance", IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS) / 1e18);
        console.log("Stakingvault ETH balance", address(stakingVault).balance);
        console.log("====================================");
    }

    function test_Fork_EnableStakingAndVerify() public {
        uint256 initialTokensForStaking = unaiToken.tokensForStaking();
        uint256 initialTokensForOperations = unaiToken.tokensForOperations();
        uint256 initialTokensForLiquidity = unaiToken.tokensForLiquidity();
        uint256 initialTokensForDev = unaiToken.tokensForDev();
        uint256 initialTokensForBurn = unaiToken.tokensForBurn();

        //console log contract variables
        console.log("tokensForOperations", initialTokensForOperations / 1e18);
        console.log("tokensForLiquidity", initialTokensForLiquidity / 1e18);
        console.log("tokensForDev", initialTokensForDev / 1e18);
        console.log("tokensForBurn", initialTokensForBurn / 1e18);
        console.log("tokensForStaking", initialTokensForStaking / 1e18);
        console.log("swapTokensAtAmount", unaiToken.swapTokensAtAmount() / 1e18);

        //log contract token balance
        console.log("Contract token balance", IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS) / 1e18);

        // staking is enabled from setup function
        vm.prank(owner);

        // Perform a buy to accumulate staking tokens
        uint256 buyEthAmount = 1 ether;
        buyTokens(user1, buyEthAmount);

        // get user1 balance
        uint256 user1Balance = IERC20(UNAI_ADDRESS).balanceOf(user1);
        console.log("User1 balance", user1Balance);
        assertGt(user1Balance, 0, "User1 should have some tokens after buying");

        // console differences in tokensFor balances
        uint256 diffTokensForOperations =
            unaiToken.tokensForOperations() - initialTokensForOperations;
        uint256 diffTokensForLiquidity = unaiToken.tokensForLiquidity() - initialTokensForLiquidity;
        uint256 diffTokensForDev = unaiToken.tokensForDev() - initialTokensForDev;
        uint256 diffTokensForBurn = unaiToken.tokensForBurn() - initialTokensForBurn;
        uint256 diffTokensForStaking = unaiToken.tokensForStaking() - initialTokensForStaking;

        //console log contract variables
        console.log("diffTokensForOperations", diffTokensForOperations / 1e18);
        console.log("diffTokensForLiquidity", diffTokensForLiquidity / 1e18);
        console.log("diffTokensForDev", diffTokensForDev / 1e18);
        console.log("diffTokensForBurn", diffTokensForBurn / 1e18);
        console.log("diffTokensForStaking", diffTokensForStaking / 1e18);

        buyTokens(user2, buyEthAmount);

        // get user2 balance
        uint256 user2Balance = IERC20(UNAI_ADDRESS).balanceOf(user2);
        console.log("User2 balance", user2Balance);

        // console differences in tokensFor balances
        diffTokensForOperations = unaiToken.tokensForOperations() - initialTokensForOperations;
        diffTokensForLiquidity = unaiToken.tokensForLiquidity() - initialTokensForLiquidity;
        diffTokensForDev = unaiToken.tokensForDev() - initialTokensForDev;
        diffTokensForBurn = unaiToken.tokensForBurn() - initialTokensForBurn;
        diffTokensForStaking = unaiToken.tokensForStaking() - initialTokensForStaking;

        //console log contract variables
        console.log("diffTokensForOperations1", diffTokensForOperations / 1e18);
        console.log("diffTokensForLiquidity1", diffTokensForLiquidity / 1e18);
        console.log("diffTokensForDev1", diffTokensForDev / 1e18);
        console.log("diffTokensForBurn1", diffTokensForBurn / 1e18);
        console.log("diffTokensForStaking1", diffTokensForStaking / 1e18);

        // set staking fee to 0
        vm.prank(owner);
        unaiToken.setSwapStakingEnabled(false);

        sellTokens(user1, user1Balance);

        // // console differences in tokensFor balances
        // diffTokensForOperations = unaiToken.tokensForOperations() - initialTokensForOperations;
        // diffTokensForLiquidity = unaiToken.tokensForLiquidity() - initialTokensForLiquidity;
        // diffTokensForDev = unaiToken.tokensForDev() - initialTokensForDev;
        // diffTokensForBurn = unaiToken.tokensForBurn() - initialTokensForBurn;
        // diffTokensForStaking = unaiToken.tokensForStaking() - initialTokensForStaking;

        // //console log contract variables
        // console.log("diffTokensForOperations2", diffTokensForOperations / 1e18);
        // console.log("diffTokensForLiquidity2", diffTokensForLiquidity / 1e18);
        // console.log("diffTokensForDev2", diffTokensForDev / 1e18);
        // console.log("diffTokensForBurn2", diffTokensForBurn / 1e18);
        // console.log("diffTokensForStaking2", diffTokensForStaking / 1e18);

        // sellTokens(user2, user2Balance);

        // //buy tokens for user1
        // buyTokens(user1, buyEthAmount);
        // buyTokens(user2, buyEthAmount);

        // user1Balance = IERC20(UNAI_ADDRESS).balanceOf(user1);
        // user2Balance = IERC20(UNAI_ADDRESS).balanceOf(user2);

        // sellTokens(user1, user1Balance);
        // sellTokens(user2, user2Balance);

        // // Initial staking tokens
        // uint256 initialStakingTokens = unaiToken.tokensForStaking();
        // uint256 initialContractBalance = IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS);

        // emit log_named_uint("Initial tokensForStaking", initialStakingTokens);
        // emit log_named_uint("Initial contract token balance", initialContractBalance);

        // // Perform a sell that should trigger staking fee accumulation
        // uint256 sellAmount = 1000 * 1e18; // Adjust based on token decimals and available balance
        // sellTokens(user1, sellAmount);

        // // Final staking tokens
        // uint256 finalStakingTokens = unaiToken.tokensForStaking();
        // uint256 finalContractBalance = IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS);

        // emit log_named_uint("Final tokensForStaking", finalStakingTokens);
        // emit log_named_uint("Final contract token balance", finalContractBalance);

        // // Calculate expected staking fee
        // uint256 stakingFeePercentage = unaiToken.sellStakingRewardsFee();
        // uint256 expectedStakingFee = (sellAmount * stakingFeePercentage) / 100;

        // emit log_named_uint("Expected staking fee", expectedStakingFee);
        // emit log_named_uint("Actual staking fee", finalStakingTokens - initialStakingTokens);

        // // Assert that staking tokens have increased correctly
        // assertEq(
        //     finalStakingTokens - initialStakingTokens,
        //     expectedStakingFee,
        //     "Staking rewards fee should be accumulated correctly"
        // );

        // Optionally, verify the contract's token balance
        // This depends on your contract's logic
    }

    //test setting staking fee to 0, dev fee to 2, and use dev wallet for staking contract
    function test_Fork_SetFeesAndDevWallet() public {
        // Initial dev tokens
        uint256 initialDevTokens = unaiToken.tokensForDev();
        uint256 initialContractBalance = IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS);
        console.log("Stakingvault ETH balance", address(stakingVault).balance);

        emit log_named_uint("Initial dev tokens", initialDevTokens);
        emit log_named_uint("Initial contract token balance", initialContractBalance);

        //set staking fee to 0 and dev fee to 1
        vm.startPrank(owner);
        unaiToken.setSwapStakingEnabled(false);
        unaiToken.updateBuyFees(2, 1, 1, 0, 0);
        unaiToken.updateSellFees(2, 1, 1, 0, 0);

        //set dev wallet to staking contract
        unaiToken.setDevAddress(address(stakingVault));
        vm.stopPrank();

        // Perform a buy to accumulate staking tokens
        uint256 buyEthAmount = 3 ether;
        buyTokens(user1, buyEthAmount);
        buyTokens(user2, buyEthAmount);

        //buy tokens for user1
        buyTokens(user1, buyEthAmount);
        buyTokens(user2, buyEthAmount);

        // Perform a sell that should trigger staking fee accumulation
        uint256 sellAmount = 100_000 * 1e18; // Adjust based on token decimals and available balance
        sellTokens(user1, sellAmount);
        sellTokens(user2, sellAmount);

        // Final dev tokens
        uint256 finalDevTokens = unaiToken.tokensForDev();
        uint256 finalContractBalance = IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS);

        emit log_named_uint("Final dev tokens", finalDevTokens);
        emit log_named_uint("Final contract token balance", finalContractBalance);
        console.log("Stakingvault ETH balance", address(stakingVault).balance);
    }

    // function test_Fork_StakingRewardsSwapAndDistribution() public {
    //     // Enable staking swap
    //     vm.prank(owner);
    //     unaiToken.setSwapStakingEnabled(true);

    //     // Lower the swap threshold to allow the swap to happen
    //     uint256 newSwapAmount = 1000 ether;
    //     vm.prank(owner);
    //     unaiToken.updateSwapTokensAtAmount(newSwapAmount);

    //     // Perform multiple sells to accumulate staking tokens
    //     uint256 sellAmount = 1000 * 1e18;

    //     // User1 buys tokens
    //     buyTokens(user1, 1 ether);

    //     // User1 sells tokens to accumulate staking tokens
    //     sellTokens(user1, sellAmount);

    //     // Check that staking rewards tokens have accumulated
    //     uint256 stakingRewardsTokens = unaiToken.tokensForStaking();
    //     emit log_named_uint("Staking rewards tokens before swap", stakingRewardsTokens);
    //     assertGt(stakingRewardsTokens, 0, "Staking rewards tokens should accumulate after sell");

    //     // Check the staking vault's ETH balance before swap
    //     uint256 stakingEthBalanceBefore = address(stakingVault).balance;

    //     // Perform the swap back
    //     vm.prank(owner);
    //     unaiToken.forceSwapBack();

    //     // Check staking rewards tokens after swap
    //     uint256 stakingRewardsTokensAfter = unaiToken.tokensForStaking();
    //     emit log_named_uint("Staking rewards tokens after swap", stakingRewardsTokensAfter);
    //     assertEq(stakingRewardsTokensAfter, 0, "Staking rewards tokens should be reset after swap");

    //     // Check the staking vault's ETH balance after swap
    //     uint256 stakingEthBalanceAfter = address(stakingVault).balance;
    //     emit log_named_uint("Staking vault ETH balance after swap", stakingEthBalanceAfter);

    //     // Ensure that ETH was sent to the staking vault
    //     assertGt(
    //         stakingEthBalanceAfter,
    //         stakingEthBalanceBefore,
    //         "Staking vault ETH balance should increase after swap"
    //     );
    // }

    // function test_Fork_StakingRewardsAccumulateWithoutSwap() public {
    //     // Disable staking swap
    //     vm.prank(owner);
    //     unaiToken.setSwapStakingEnabled(false);

    //     // Perform a sell to accumulate staking tokens
    //     uint256 sellAmount = 1000 * 1e18; // Adjust based on token decimals and available balance

    //     // User1 buys tokens
    //     buyTokens(user1, 1 ether);

    //     // Record initial staking tokens
    //     uint256 initialStakingTokens = unaiToken.tokensForStaking();

    //     // Perform a sell
    //     sellTokens(user1, sellAmount);

    //     // Check that staking rewards tokens have accumulated
    //     uint256 finalStakingTokens = unaiToken.tokensForStaking();
    //     emit log_named_uint("Staking rewards tokens after sell", finalStakingTokens);

    //     // Ensure staking tokens have increased
    //     assertGt(
    //         finalStakingTokens,
    //         initialStakingTokens,
    //         "Staking rewards tokens should accumulate after sell when swap is disabled"
    //     );

    //     // Ensure that forceSwapBack does not reset staking tokens when swap is disabled
    //     vm.prank(owner);
    //     unaiToken.forceSwapBack();

    //     uint256 stakingTokensAfterForceSwap = unaiToken.tokensForStaking();
    //     emit log_named_uint(
    //         "Staking rewards tokens after forceSwapBack", stakingTokensAfterForceSwap
    //     );

    //     assertEq(
    //         stakingTokensAfterForceSwap,
    //         finalStakingTokens,
    //         "Staking rewards tokens should not change when swap is disabled"
    //     );
    // }

    // function test_Fork_TokensForStakingMatchesContractBalance() public {
    //     // Enable staking swap
    //     vm.prank(owner);
    //     unaiToken.setSwapStakingEnabled(true);

    //     // User1 buys tokens
    //     buyTokens(user1, 1 ether);

    //     // Perform a sell to accumulate staking tokens
    //     uint256 sellAmount = 1000 * 1e18; // Adjust based on token decimals and available balance
    //     sellTokens(user1, sellAmount);

    //     // Get tokensForStaking from contract
    //     uint256 tokensForStaking = unaiToken.tokensForStaking();

    //     // Get actual tokens in contract for staking
    //     // Assuming staking tokens are held by the contract
    //     uint256 contractStakingBalance = IERC20(UNAI_ADDRESS).balanceOf(UNAI_ADDRESS);

    //     emit log_named_uint("Tokens for staking (contract state)", tokensForStaking);
    //     emit log_named_uint("Actual tokens in contract for staking", contractStakingBalance);

    //     // Assert that tokensForStaking matches contract balance
    //     // Adjust based on your contract's actual logic
    //     assertEq(
    //         tokensForStaking,
    //         contractStakingBalance,
    //         "tokensForStaking should match the contract's staking token balance"
    //     );
    // }
}
