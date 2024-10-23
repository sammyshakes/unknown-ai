// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract StakingVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Primary Staking Token
    address public unaiToken;

    // ETH rewards variables
    uint256 public constant SHARE_TIME_FRAME = 90 days;
    uint256 public totalShares;
    uint256 public accEthRewardPerShare; // Scaled by 1e12
    uint256 public lastUpdateTime;
    uint256 public totalStaked;
    uint256 public totalEthRewardsDistributed;
    uint256 public totalEthRewardsReceived;

    // UNAI rewards variables
    uint256 public accUnaiRewardPerShare; // Scaled by 1e12
    uint256 public totalUnaiRewardsDistributed;
    uint256 public totalUnaiRewardsReceived;

    // Stake structure
    struct Stake {
        uint256 amount; // Amount of tokens staked
        uint256 startTime; // Timestamp when stake was created
        uint256 lockDuration; // Duration of the stake
        uint256 shares; // Calculated shares based on amount and lock duration
        uint256 ethRewardDebt; // ETH reward debt
        uint256 unaiRewardDebt; // UNAI reward debt
    }

    mapping(address => Stake[]) public userStakes;
    mapping(address => bool) public authorizedMarketplaces;

    // Events
    event Staked(
        address indexed user, uint256 indexed stakeId, uint256 amount, uint256 lockDuration
    );
    event Unstaked(
        address indexed user,
        uint256 indexed stakeId,
        uint256 amount,
        uint256 ethReward,
        uint256 unaiReward
    );
    event EthRewardsDistributed(uint256 totalRewards);
    event EthRewardsClaimed(address indexed user, uint256 indexed stakeId, uint256 reward);
    event UnaiRewardsDistributed(uint256 totalRewards);
    event UnaiRewardsClaimed(address indexed user, uint256 indexed stakeId, uint256 reward);
    event StakeTransferred(
        address indexed from, address indexed to, uint256 oldStakeId, uint256 newStakeId
    );
    event MarketplaceAuthorizationSet(address indexed marketplace, bool isAuthorized);
    event UnaiRewardsDeposited(address indexed owner, uint256 amount);

    /**
     * @dev Constructor sets the staking token.
     * @param _unaiToken Address of the ERC20 token to be staked and used as a reward.
     */
    constructor(address _unaiToken) Ownable(msg.sender) {
        require(_unaiToken != address(0), "Invalid staking token address");
        unaiToken = _unaiToken;
        lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Updates the accumulated rewards per share for ETH and UNAI rewards.
     */
    function updateRewards() public {
        if (block.timestamp <= lastUpdateTime) {
            return;
        }

        if (totalShares > 0) {
            // Update ETH rewards
            uint256 newEthRewards = totalEthRewardsReceived - totalEthRewardsDistributed;
            require(
                newEthRewards + totalEthRewardsDistributed >= totalEthRewardsReceived,
                "ETH rewards overflow"
            );
            if (newEthRewards > 0) {
                accEthRewardPerShare += (newEthRewards * 1e12) / totalShares;
                totalEthRewardsDistributed += newEthRewards;
                emit EthRewardsDistributed(newEthRewards);
            }

            // Update UNAI rewards
            uint256 newUnaiRewards = totalUnaiRewardsReceived - totalUnaiRewardsDistributed;
            require(
                newUnaiRewards + totalUnaiRewardsDistributed >= totalUnaiRewardsReceived,
                "UNAI rewards overflow"
            );

            if (newUnaiRewards > 0) {
                accUnaiRewardPerShare += (newUnaiRewards * 1e12) / totalShares;
                totalUnaiRewardsDistributed += newUnaiRewards;
                emit UnaiRewardsDistributed(newUnaiRewards);
            }
        }

        lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Allows users to stake a specified amount of the staking token for a lock duration.
     * @param amount The amount of tokens to stake.
     * @param lockDuration The duration to lock the stake for (minimum 30 days).
     */
    function stake(uint256 amount, uint256 lockDuration) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(lockDuration >= 30 days, "Lock duration must be at least 30 days");

        updateRewards();

        uint256 shares = (amount * lockDuration) / SHARE_TIME_FRAME;
        Stake memory newStake = Stake({
            amount: amount,
            startTime: block.timestamp,
            lockDuration: lockDuration,
            shares: shares,
            ethRewardDebt: (shares * accEthRewardPerShare) / 1e12,
            unaiRewardDebt: (shares * accUnaiRewardPerShare) / 1e12
        });

        userStakes[msg.sender].push(newStake);
        uint256 stakeId = userStakes[msg.sender].length - 1;
        totalShares += shares;
        totalStaked += amount;

        IERC20(unaiToken).safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, stakeId, amount, lockDuration);
    }

    /**
     * @dev Allows users to unstake their tokens after the lock period and claim rewards.
     * @param stakeId The ID of the stake to unstake.
     */
    function unstake(uint256 stakeId) external nonReentrant {
        require(stakeId < userStakes[msg.sender].length, "Invalid stake ID");
        Stake storage userStake = userStakes[msg.sender][stakeId];
        require(
            block.timestamp >= userStake.startTime + userStake.lockDuration, "Lock period not over"
        );

        updateRewards();

        uint256 amount = userStake.amount;
        uint256 shares = userStake.shares;

        // Calculate pending ETH rewards
        uint256 pendingEth = (shares * accEthRewardPerShare) / 1e12 - userStake.ethRewardDebt;

        // Calculate pending UNAI rewards
        uint256 pendingUnai = (shares * accUnaiRewardPerShare) / 1e12 - userStake.unaiRewardDebt;

        // Update state before external calls
        totalShares -= shares;
        totalStaked -= amount;

        // Remove the stake by swapping with the last element and popping
        userStakes[msg.sender][stakeId] = userStakes[msg.sender][userStakes[msg.sender].length - 1];
        userStakes[msg.sender].pop();

        // Transfer staked tokens back to the user
        IERC20(unaiToken).safeTransfer(msg.sender, amount);

        // Transfer ETH rewards
        if (pendingEth > 0) {
            (bool success,) = msg.sender.call{value: pendingEth}("");
            require(success, "ETH transfer failed");
            emit EthRewardsClaimed(msg.sender, stakeId, pendingEth);
        }

        // Transfer UNAI rewards
        if (pendingUnai > 0) {
            IERC20(unaiToken).safeTransfer(msg.sender, pendingUnai);
            emit UnaiRewardsClaimed(msg.sender, stakeId, pendingUnai);
        }

        emit Unstaked(msg.sender, stakeId, amount, pendingEth, pendingUnai);
    }

    /**
     * @dev Allows users to claim their pending rewards without unstaking.
     * @param stakeId The ID of the stake to claim rewards from.
     */
    function claimRewards(uint256 stakeId) external nonReentrant {
        require(stakeId < userStakes[msg.sender].length, "Invalid stake ID");
        Stake storage userStake = userStakes[msg.sender][stakeId];

        updateRewards();

        // Calculate pending ETH rewards
        uint256 pendingEth =
            (userStake.shares * accEthRewardPerShare) / 1e12 - userStake.ethRewardDebt;

        // Calculate pending UNAI rewards
        uint256 pendingUnai =
            (userStake.shares * accUnaiRewardPerShare) / 1e12 - userStake.unaiRewardDebt;

        require(pendingEth > 0 || pendingUnai > 0, "No rewards to claim");

        // Transfer ETH rewards
        if (pendingEth > 0) {
            (bool success,) = msg.sender.call{value: pendingEth}("");
            require(success, "ETH transfer failed");
            emit EthRewardsClaimed(msg.sender, stakeId, pendingEth);
        }

        // Transfer UNAI rewards
        if (pendingUnai > 0) {
            IERC20(unaiToken).safeTransfer(msg.sender, pendingUnai);
            emit UnaiRewardsClaimed(msg.sender, stakeId, pendingUnai);
        }

        // Update reward debts to current values
        userStakes[msg.sender][stakeId].ethRewardDebt =
            (userStakes[msg.sender][stakeId].shares * accEthRewardPerShare) / 1e12;
        userStakes[msg.sender][stakeId].unaiRewardDebt =
            (userStakes[msg.sender][stakeId].shares * accUnaiRewardPerShare) / 1e12;

        emit Unstaked(msg.sender, stakeId, 0, pendingEth, pendingUnai); // Using Unstaked event to log reward claims
    }

    /**
     * @dev Returns the pending ETH and UNAI rewards for a user's stake.
     * @param user The address of the user.
     * @param stakeId The ID of the stake.
     * @return ethPending The pending ETH rewards.
     * @return unaiPending The pending UNAI rewards.
     */
    function pendingRewards(address user, uint256 stakeId)
        external
        view
        returns (uint256 ethPending, uint256 unaiPending)
    {
        require(stakeId < userStakes[user].length, "Invalid stake ID");
        Stake storage userStake = userStakes[user][stakeId];

        uint256 _accEthRewardPerShare = accEthRewardPerShare;
        uint256 _accUnaiRewardPerShare = accUnaiRewardPerShare;

        // Calculate ETH rewards
        if (block.timestamp > lastUpdateTime && totalShares > 0) {
            uint256 newEthRewards = totalEthRewardsReceived - totalEthRewardsDistributed;
            if (newEthRewards > 0) {
                _accEthRewardPerShare += ((newEthRewards * 1e12) / totalShares);
            }
        }

        ethPending = (userStake.shares * _accEthRewardPerShare) / 1e12 - userStake.ethRewardDebt;

        // Calculate UNAI rewards
        if (block.timestamp > lastUpdateTime && totalShares > 0) {
            uint256 newUnaiRewards = totalUnaiRewardsReceived - totalUnaiRewardsDistributed;
            if (newUnaiRewards > 0) {
                _accUnaiRewardPerShare += ((newUnaiRewards * 1e12) / totalShares);
            }
        }

        unaiPending = (userStake.shares * _accUnaiRewardPerShare) / 1e12 - userStake.unaiRewardDebt;
    }

    /**
     * @dev Extends the lock duration of an existing stake.
     * @param stakeId The ID of the stake to extend.
     * @param additionalLockDuration The additional time to add to the lock duration.
     */
    function extendStake(uint256 stakeId, uint256 additionalLockDuration) external nonReentrant {
        require(stakeId < userStakes[msg.sender].length, "Invalid stake ID");
        require(additionalLockDuration > 0, "Additional lock duration must be greater than 0");
        require(additionalLockDuration <= 365 days, "Cannot extend more than 365 days");

        Stake storage userStake = userStakes[msg.sender][stakeId];
        uint256 currentTime = block.timestamp;
        uint256 stakeEndTime = userStake.startTime + userStake.lockDuration;

        require(currentTime < stakeEndTime, "Cannot extend expired stake");

        updateRewards();

        // Calculate and transfer pending rewards
        uint256 pendingEth =
            (userStake.shares * accEthRewardPerShare) / 1e12 - userStake.ethRewardDebt;
        uint256 pendingUnai =
            (userStake.shares * accUnaiRewardPerShare) / 1e12 - userStake.unaiRewardDebt;

        if (pendingEth > 0) {
            (bool success,) = msg.sender.call{value: pendingEth}("");
            require(success, "ETH transfer failed");
            emit EthRewardsClaimed(msg.sender, stakeId, pendingEth);
        }
        if (pendingUnai > 0) {
            IERC20(unaiToken).safeTransfer(msg.sender, pendingUnai);
            emit UnaiRewardsClaimed(msg.sender, stakeId, pendingUnai);
        }

        // Extend the stake
        uint256 remainingDuration = stakeEndTime > currentTime ? stakeEndTime - currentTime : 0;
        uint256 newLockDuration = remainingDuration + additionalLockDuration;
        uint256 additionalShares = (userStake.amount * additionalLockDuration) / SHARE_TIME_FRAME;

        userStake.lockDuration = newLockDuration;
        userStake.shares += additionalShares;

        totalShares += additionalShares;

        // Update reward debts
        userStake.ethRewardDebt = (userStake.shares * accEthRewardPerShare) / 1e12;
        userStake.unaiRewardDebt = (userStake.shares * accUnaiRewardPerShare) / 1e12;

        emit Staked(msg.sender, stakeId, 0, additionalLockDuration); // Optionally, emit a separate event for extension
    }

    /**
     * @dev Allows authorized marketplaces to transfer a user's stake to another address.
     * @param from The address from which the stake is transferred.
     * @param to The address to which the stake is transferred.
     * @param stakeId The ID of the stake to transfer.
     */
    function transferStake(address from, address to, uint256 stakeId) external nonReentrant {
        require(authorizedMarketplaces[msg.sender], "Caller is not an authorized marketplace");
        require(stakeId < userStakes[from].length, "Invalid stake ID");
        require(to != address(0), "Cannot transfer to zero address");

        updateRewards(); // Update rewards before performing any transfers.

        // **Copy the stake data into memory**
        Stake memory transferredStake = userStakes[from][stakeId];
        uint256 shares = transferredStake.shares;

        // Calculate pending ETH and UNAI rewards for the original owner
        uint256 pendingEth = (shares * accEthRewardPerShare) / 1e12 - transferredStake.ethRewardDebt;
        uint256 pendingUnai =
            (shares * accUnaiRewardPerShare) / 1e12 - transferredStake.unaiRewardDebt;

        // Transfer pending ETH rewards to the original owner
        if (pendingEth > 0) {
            (bool success,) = from.call{value: pendingEth}("");
            require(success, "ETH transfer failed");
            emit EthRewardsClaimed(from, stakeId, pendingEth);
        }

        // Transfer pending UNAI rewards to the original owner
        if (pendingUnai > 0) {
            IERC20(unaiToken).safeTransfer(from, pendingUnai);
            emit UnaiRewardsClaimed(from, stakeId, pendingUnai);
        }

        // **Remove the stake from the original owner**
        userStakes[from][stakeId] = userStakes[from][userStakes[from].length - 1]; // Replace with the last stake
        userStakes[from].pop(); // Remove the last element

        // **Update reward debts for the new owner**
        transferredStake.ethRewardDebt = (shares * accEthRewardPerShare) / 1e12;
        transferredStake.unaiRewardDebt = (shares * accUnaiRewardPerShare) / 1e12;

        // **Add the stake to the new owner's list**
        userStakes[to].push(transferredStake);
        uint256 newStakeId = userStakes[to].length - 1; // New ID based on the new owner's stake list

        emit StakeTransferred(from, to, stakeId, newStakeId);
    }

    /**
     * @dev Returns the number of active stakes a user has.
     * @param user The address of the user.
     * @return The count of stakes.
     */
    function getUserStakesCount(address user) external view returns (uint256) {
        return userStakes[user].length;
    }

    /**
     * @dev Allows anyone to deposit UNAI rewards into the contract.
     * @param amount The amount of UNAI tokens to deposit.
     */
    function depositUnaiRewards(uint256 amount) external {
        // Transfer the UNAI tokens to this contract
        IERC20(unaiToken).safeTransferFrom(msg.sender, address(this), amount);

        // Update total UNAI rewards received
        totalUnaiRewardsReceived += amount;

        // Call updateRewards after the tokens are received
        updateRewards();

        emit UnaiRewardsDeposited(msg.sender, amount);
    }

    /**
     * @dev Sets authorization for marketplaces to transfer stakes.
     * @param marketplace The address of the marketplace.
     * @param isAuthorized Whether the marketplace is authorized.
     */
    function setMarketplaceAuthorization(address marketplace, bool isAuthorized)
        external
        onlyOwner
    {
        authorizedMarketplaces[marketplace] = isAuthorized;
        emit MarketplaceAuthorizationSet(marketplace, isAuthorized);
    }

    /**
     * @dev Receive function to accept ETH and distribute rewards.
     */
    receive() external payable {
        totalEthRewardsReceived += msg.value;
        updateRewards();
        emit EthRewardsDistributed(msg.value);
    }

    /**
     * @dev Allows the owner to withdraw any stake from the contract in case of emergency.
     */
    function emergencyWithdrawal(address _user, uint256 _stakeId) external onlyOwner {
        require(_stakeId < userStakes[_user].length, "Invalid stake ID");
        Stake storage userStake = userStakes[_user][_stakeId];
        uint256 amount = userStake.amount;
        uint256 shares = userStake.shares;

        // Calculate pending ETH rewards
        uint256 pendingEth = (shares * accEthRewardPerShare) / 1e12 - userStake.ethRewardDebt;

        // Calculate pending UNAI rewards
        uint256 pendingUnai = (shares * accUnaiRewardPerShare) / 1e12 - userStake.unaiRewardDebt;

        // Update state before external calls
        totalShares -= shares;
        totalStaked -= amount;

        // Remove the stake by swapping with the last element and popping
        userStakes[_user][_stakeId] = userStakes[_user][userStakes[_user].length - 1];
        userStakes[_user].pop();

        // Transfer staked tokens back to the user
        IERC20(unaiToken).safeTransfer(_user, amount);

        // Transfer ETH rewards
        if (pendingEth > 0) {
            (bool success,) = _user.call{value: pendingEth}("");
            require(success, "ETH transfer failed");
            emit EthRewardsClaimed(_user, _stakeId, pendingEth);
        }

        // Transfer UNAI rewards
        if (pendingUnai > 0) {
            IERC20(unaiToken).safeTransfer(_user, pendingUnai);
            emit UnaiRewardsClaimed(_user, _stakeId, pendingUnai);
        }

        emit Unstaked(_user, _stakeId, amount, pendingEth, pendingUnai);
    }
}
