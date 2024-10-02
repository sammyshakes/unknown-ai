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
    uint256 public accEthRewardPerShare;
    uint256 public lastUpdateTime;
    uint256 public totalStaked;
    uint256 public totalEthRewardsDistributed;

    // ERC20 rewards management
    struct RewardToken {
        address token; // The ERC20 token used for rewards
        uint256 accRewardPerShare; // Accumulated rewards per share, scaled by 1e18
        uint256 totalRewards; // Total rewards distributed for this token
        bool exists; // Flag to check existence
    }

    // Mapping from reward token address to RewardToken struct
    mapping(address => RewardToken) public rewardTokens;

    // Mapping from reward token address to total ERC20 rewards distributed
    mapping(address => uint256) public totalERC20RewardsDistributed;

    // Array of reward token addresses for iteration
    address[] public rewardTokenList;

    // Stake structure
    struct Stake {
        uint256 amount; // Amount of tokens staked
        uint256 startTime; // Timestamp when stake was created
        uint256 lockDuration; // Duration of the stake
        uint256 shares; // Calculated shares based on amount and lock duration
        uint256 ethRewardDebt; // ETH reward debt
    }

    // Mapping from user to stake ID to reward debt per token
    mapping(address => mapping(uint256 => mapping(address => uint256))) public userRewardDebt;

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
        uint256[] erc20Rewards
    );
    event EthRewardsDistributed(uint256 totalRewards);
    event EthRewardsClaimed(address indexed user, uint256 indexed stakeId, uint256 reward);
    event ERC20RewardAdded(address indexed rewardToken);
    event ERC20RewardRemoved(address indexed rewardToken);
    event ERC20RewardsDistributed(address indexed rewardToken, uint256 totalRewards);
    event ERC20RewardsClaimed(
        address indexed user, uint256 indexed stakeId, address indexed rewardToken, uint256 reward
    );
    event StakeTransferred(address indexed from, address indexed to, uint256 stakeId);
    event MarketplaceAuthorizationSet(address indexed marketplace, bool isAuthorized);

    /**
     * @dev Constructor sets the staking token and initializes it as the first reward token.
     * @param _unaiToken Address of the ERC20 token to be staked and used as an initial reward.
     */
    constructor(address _unaiToken) Ownable(msg.sender) {
        require(_unaiToken != address(0), "Invalid staking token address");
        unaiToken = _unaiToken;
        lastUpdateTime = block.timestamp;

        // Initialize unaiToken as the first reward token
        rewardTokens[_unaiToken] =
            RewardToken({token: _unaiToken, accRewardPerShare: 0, totalRewards: 0, exists: true});
        rewardTokenList.push(_unaiToken);

        emit ERC20RewardAdded(_unaiToken);
    }

    /**
     * @dev Adds a new ERC20 reward token.
     * Can only be called by the contract owner.
     * @param _rewardToken The address of the new ERC20 reward token.
     */
    function addERC20Reward(address _rewardToken) external onlyOwner {
        require(_rewardToken != address(0), "Invalid reward token address");
        require(!rewardTokens[_rewardToken].exists, "Reward token already added");

        // Prevent adding unaiToken again if it's already initialized as a reward token
        if (_rewardToken != unaiToken) {
            rewardTokens[_rewardToken] = RewardToken({
                token: _rewardToken,
                accRewardPerShare: 0,
                totalRewards: 0,
                exists: true
            });
            rewardTokenList.push(_rewardToken);
            emit ERC20RewardAdded(_rewardToken);
        } else {
            revert("unaiToken is already a reward token");
        }
    }

    /**
     * @dev Removes an existing ERC20 reward token.
     * Can only be called by the contract owner.
     * @param _rewardToken The address of the ERC20 reward token to remove.
     */
    function removeERC20Reward(address _rewardToken) external onlyOwner {
        require(_rewardToken != address(0), "Invalid reward token address");
        require(rewardTokens[_rewardToken].exists, "Reward token not found");

        // Prevent removing unaiToken to maintain its role as a reward token
        require(_rewardToken != unaiToken, "Cannot remove unaiToken as a reward token");

        // Remove from mapping
        delete rewardTokens[_rewardToken];

        // Remove from array
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            if (rewardTokenList[i] == _rewardToken) {
                rewardTokenList[i] = rewardTokenList[rewardTokenList.length - 1];
                rewardTokenList.pop();
                break;
            }
        }

        emit ERC20RewardRemoved(_rewardToken);
    }

    /**
     * @dev Updates the accumulated rewards per share for ETH and all ERC20 rewards.
     */
    function updateRewards() public {
        if (block.timestamp <= lastUpdateTime) {
            return;
        }

        if (totalShares > 0) {
            // Update ETH rewards
            uint256 ethBalance = address(this).balance;
            uint256 newEthRewards = ethBalance - totalEthRewardsDistributed;
            if (newEthRewards > 0) {
                accEthRewardPerShare += (newEthRewards * 1e18) / totalShares;
                totalEthRewardsDistributed += newEthRewards;
                emit EthRewardsDistributed(newEthRewards);
            }

            // Update ERC20 rewards
            for (uint256 i = 0; i < rewardTokenList.length; i++) {
                address currentReward = rewardTokenList[i];
                uint256 currentBalance;

                if (currentReward == unaiToken) {
                    // For unaiToken, exclude staked amount from balance
                    currentBalance = IERC20(currentReward).balanceOf(address(this)) - totalStaked;
                } else {
                    // For other ERC20 reward tokens, use the full balance
                    currentBalance = IERC20(currentReward).balanceOf(address(this));
                }

                uint256 newERC20Rewards =
                    currentBalance - totalERC20RewardsDistributed[currentReward];
                if (newERC20Rewards > 0) {
                    rewardTokens[currentReward].accRewardPerShare +=
                        (newERC20Rewards * 1e18) / totalShares;
                    rewardTokens[currentReward].totalRewards += newERC20Rewards;
                    totalERC20RewardsDistributed[currentReward] += newERC20Rewards;
                    emit ERC20RewardsDistributed(currentReward, newERC20Rewards);
                }
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
            ethRewardDebt: (shares * accEthRewardPerShare) / 1e18
        });

        userStakes[msg.sender].push(newStake);
        uint256 stakeId = userStakes[msg.sender].length - 1;
        totalShares += shares;
        totalStaked += amount;

        IERC20(unaiToken).safeTransferFrom(msg.sender, address(this), amount);

        // Initialize ERC20 reward debts
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            address currentReward = rewardTokenList[i];
            userRewardDebt[msg.sender][stakeId][currentReward] =
                (shares * rewardTokens[currentReward].accRewardPerShare) / 1e18;
        }

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
        uint256 pendingEth = (shares * accEthRewardPerShare) / 1e18 - userStake.ethRewardDebt;

        // Calculate pending ERC20 rewards
        uint256[] memory pendingERC20 = new uint256[](rewardTokenList.length);
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            address currentReward = rewardTokenList[i];
            uint256 pending = (shares * rewardTokens[currentReward].accRewardPerShare) / 1e18
                - userRewardDebt[msg.sender][stakeId][currentReward];
            if (pending > 0) {
                pendingERC20[i] = pending;
            }
        }

        // Update state before external calls
        totalShares -= shares;
        totalStaked -= amount;

        // Remove the stake by swapping with the last element and popping
        userStakes[msg.sender][stakeId] = userStakes[msg.sender][userStakes[msg.sender].length - 1];
        userStakes[msg.sender].pop();

        // Update ETH reward debt
        // (No need to set to zero since the stake is removed)

        // Update ERC20 reward debts
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            address currentReward = rewardTokenList[i];
            // Since the stake is being removed, no further tracking is needed
            // Optionally, you can delete the mapping entry
            delete userRewardDebt[msg.sender][stakeId][currentReward];
        }

        // Transfer staked tokens back to the user
        IERC20(unaiToken).safeTransfer(msg.sender, amount);

        // Transfer ETH rewards
        if (pendingEth > 0) {
            (bool success,) = msg.sender.call{value: pendingEth}("");
            require(success, "ETH transfer failed");
            emit EthRewardsClaimed(msg.sender, stakeId, pendingEth);
        }

        // Transfer ERC20 rewards
        uint256[] memory transferredERC20 = new uint256[](rewardTokenList.length);
        for (uint256 i = 0; i < pendingERC20.length; i++) {
            if (pendingERC20[i] > 0) {
                address currentReward = rewardTokenList[i];
                IERC20(rewardTokens[currentReward].token).safeTransfer(msg.sender, pendingERC20[i]);
                totalERC20RewardsDistributed[currentReward] -= pendingERC20[i];
                transferredERC20[i] = pendingERC20[i];
                emit ERC20RewardsClaimed(msg.sender, stakeId, currentReward, pendingERC20[i]);
            }
        }

        emit Unstaked(msg.sender, stakeId, amount, pendingEth, transferredERC20);
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
            (userStake.shares * accEthRewardPerShare) / 1e18 - userStake.ethRewardDebt;

        // Calculate pending ERC20 rewards
        uint256[] memory pendingERC20 = new uint256[](rewardTokenList.length);
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            address currentReward = rewardTokenList[i];
            uint256 pending = (userStake.shares * rewardTokens[currentReward].accRewardPerShare)
                / 1e18 - userRewardDebt[msg.sender][stakeId][currentReward];
            if (pending > 0) {
                pendingERC20[i] = pending;
            }
        }

        bool hasRewards = pendingEth > 0;
        for (uint256 i = 0; i < pendingERC20.length; i++) {
            if (pendingERC20[i] > 0) {
                hasRewards = true;
                break;
            }
        }
        require(hasRewards, "No rewards to claim");

        // Update ETH reward debt
        if (pendingEth > 0) {
            userStake.ethRewardDebt = (userStake.shares * accEthRewardPerShare) / 1e18;
        }

        // Update ERC20 reward debts and prepare to transfer rewards
        uint256[] memory transferredERC20 = new uint256[](rewardTokenList.length);
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            if (pendingERC20[i] > 0) {
                address currentReward = rewardTokenList[i];
                userRewardDebt[msg.sender][stakeId][currentReward] =
                    (userStake.shares * rewardTokens[currentReward].accRewardPerShare) / 1e18;
                IERC20(rewardTokens[currentReward].token).safeTransfer(msg.sender, pendingERC20[i]);
                totalERC20RewardsDistributed[currentReward] -= pendingERC20[i];
                transferredERC20[i] = pendingERC20[i];
                emit ERC20RewardsClaimed(msg.sender, stakeId, currentReward, pendingERC20[i]);
            }
        }

        // Transfer ETH rewards
        if (pendingEth > 0) {
            (bool success,) = msg.sender.call{value: pendingEth}("");
            require(success, "ETH transfer failed");
            emit EthRewardsClaimed(msg.sender, stakeId, pendingEth);
        }

        // Emit Unstaked-like event for claiming rewards
        emit Unstaked(msg.sender, stakeId, 0, pendingEth, transferredERC20);
    }

    /**
     * @dev Returns the pending ETH and ERC20 rewards for a user's stake.
     * @param user The address of the user.
     * @param stakeId The ID of the stake.
     * @return ethPending The pending ETH rewards.
     * @return erc20Pending An array of pending ERC20 rewards for each reward token.
     */
    function pendingRewards(address user, uint256 stakeId)
        external
        view
        returns (uint256 ethPending, uint256[] memory erc20Pending)
    {
        require(stakeId < userStakes[user].length, "Invalid stake ID");
        Stake storage userStake = userStakes[user][stakeId];

        uint256 _accEthRewardPerShare = accEthRewardPerShare;

        // Calculate ETH rewards
        if (block.timestamp > lastUpdateTime && totalShares > 0) {
            uint256 newEthRewards = address(this).balance - totalEthRewardsDistributed;
            if (newEthRewards > 0) {
                _accEthRewardPerShare += ((newEthRewards * 1e18) / totalShares);
            }
        }

        ethPending = (userStake.shares * _accEthRewardPerShare) / 1e18 - userStake.ethRewardDebt;

        // Calculate ERC20 rewards
        erc20Pending = new uint256[](rewardTokenList.length);
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            address currentReward = rewardTokenList[i];
            uint256 _accRewardPerShare = rewardTokens[currentReward].accRewardPerShare;

            if (block.timestamp > lastUpdateTime && totalShares > 0) {
                uint256 newERC20Rewards = IERC20(currentReward).balanceOf(address(this))
                    - totalERC20RewardsDistributed[currentReward];
                if (newERC20Rewards > 0) {
                    _accRewardPerShare += ((newERC20Rewards * 1e18) / totalShares);
                }
            }

            uint256 pending = (userStake.shares * _accRewardPerShare) / 1e18
                - userRewardDebt[user][stakeId][currentReward];
            if (pending > 0) {
                erc20Pending[i] = pending;
            }
        }
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

        // Calculate pending ETH rewards before extension
        uint256 pendingEth =
            (userStake.shares * accEthRewardPerShare) / 1e18 - userStake.ethRewardDebt;

        // Calculate pending ERC20 rewards before extension
        uint256[] memory pendingERC20 = new uint256[](rewardTokenList.length);
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            address currentReward = rewardTokenList[i];
            uint256 pending = (userStake.shares * rewardTokens[currentReward].accRewardPerShare)
                / 1e18 - userRewardDebt[msg.sender][stakeId][currentReward];
            if (pending > 0) {
                pendingERC20[i] = pending;
            }
        }

        uint256 remainingDuration = stakeEndTime > currentTime ? stakeEndTime - currentTime : 0;
        uint256 newLockDuration = remainingDuration + additionalLockDuration;
        uint256 additionalShares = (userStake.amount * additionalLockDuration) / SHARE_TIME_FRAME;

        userStake.lockDuration = newLockDuration;
        userStake.shares += additionalShares;

        // Update ETH reward debt to include pending rewards
        userStake.ethRewardDebt = (userStake.shares * accEthRewardPerShare) / 1e18 - pendingEth;

        // Update ERC20 reward debts to include pending rewards
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            address currentReward = rewardTokenList[i];
            userRewardDebt[msg.sender][stakeId][currentReward] = (
                userStake.shares * rewardTokens[currentReward].accRewardPerShare
            ) / 1e18 - pendingERC20[i];
        }

        totalShares += additionalShares;

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

        updateRewards();

        Stake storage transferredStake = userStakes[from][stakeId];
        uint256 shares = transferredStake.shares;

        // Calculate pending ETH rewards
        uint256 pendingEth = (shares * accEthRewardPerShare) / 1e18 - transferredStake.ethRewardDebt;

        // Calculate pending ERC20 rewards
        uint256[] memory pendingERC20 = new uint256[](rewardTokenList.length);
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            address currentReward = rewardTokenList[i];
            uint256 pending = (shares * rewardTokens[currentReward].accRewardPerShare) / 1e18
                - userRewardDebt[from][stakeId][currentReward];
            if (pending > 0) {
                pendingERC20[i] = pending;
            }
        }

        // Update state before external calls
        // Note: totalShares remains unchanged as the stake is merely transferred

        // Remove the stake from the original owner
        userStakes[from][stakeId] = userStakes[from][userStakes[from].length - 1];
        userStakes[from].pop();

        // Add the stake to the new owner
        userStakes[to].push(transferredStake);
        uint256 newStakeId = userStakes[to].length - 1;

        // Update reward debts for the new owner
        transferredStake.ethRewardDebt = (shares * accEthRewardPerShare) / 1e18 - pendingEth;

        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            address currentReward = rewardTokenList[i];
            userRewardDebt[to][newStakeId][currentReward] =
                (shares * rewardTokens[currentReward].accRewardPerShare) / 1e18 - pendingERC20[i];
        }

        // Transfer any pending ETH rewards to the original owner
        if (pendingEth > 0) {
            (bool success,) = from.call{value: pendingEth}("");
            require(success, "ETH transfer failed");
            emit EthRewardsClaimed(from, stakeId, pendingEth);
        }

        // Transfer any pending ERC20 rewards to the original owner
        uint256[] memory transferredERC20 = new uint256[](rewardTokenList.length);
        for (uint256 i = 0; i < pendingERC20.length; i++) {
            if (pendingERC20[i] > 0) {
                address currentReward = rewardTokenList[i];
                IERC20(rewardTokens[currentReward].token).safeTransfer(from, pendingERC20[i]);
                totalERC20RewardsDistributed[currentReward] -= pendingERC20[i];
                transferredERC20[i] = pendingERC20[i];
                emit ERC20RewardsClaimed(from, stakeId, currentReward, pendingERC20[i]);
            }
        }

        emit StakeTransferred(from, to, stakeId);
    }

    // Function to deposit ERC20 rewards
    function depositERC20Rewards(address tokenAddress, uint256 amount) external {
        require(rewardTokens[tokenAddress].exists, "Reward token not found");

        // Transfer the ERC20 tokens to this contract
        IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);

        // Call updateRewards after the tokens are received
        updateRewards();
    }

    function getRewardTokenListLength() external view returns (uint256) {
        return rewardTokenList.length;
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
        updateRewards();
        emit EthRewardsDistributed(msg.value);
    }
}
