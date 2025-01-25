/*
██╗   ██╗███╗   ██╗██╗  ██╗███╗   ██╗ ██████╗ ██╗    ██╗███╗   ██╗     █████╗ ██╗
██║   ██║████╗  ██║██║ ██╔╝████╗  ██║██╔═══██╗██║    ██║████╗  ██║    ██╔══██╗██║
██║   ██║██╔██╗ ██║█████╔╝ ██╔██╗ ██║██║   ██║██║ █╗ ██║██╔██╗ ██║    ███████║██║
██║   ██║██║╚██╗██║██╔═██╗ ██║╚██╗██║██║   ██║██║███╗██║██║╚██╗██║    ██╔══██║██║
╚██████╔╝██║ ╚████║██║  ██╗██║ ╚████║╚██████╔╝╚███╔███╔╝██║ ╚████║    ██║  ██║██║
╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚═══╝    ╚═╝  ╚═╝╚═╝

███╗   ███╗██╗ ██████╗ ██████╗  █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
████╗ ████║██║██╔════╝ ██╔══██╗██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
██╔████╔██║██║██║  ███╗██████╔╝███████║   ██║   ██║██║   ██║██╔██╗ ██║
██║╚██╔╝██║██║██║   ██║██╔══██╗██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
██║ ╚═╝ ██║██║╚██████╔╝██║  ██║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
╚═╝     ╚═╝╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount)
        external
        returns (bool);
}

contract UNAIMigration is Ownable, ReentrancyGuard {
    IERC20 public immutable unaiV1;
    IERC20 public immutable unaiV2;

    // Events
    event TokensMigrated(address indexed user, uint256 amount);
    event V1TokensWithdrawn(address indexed owner, uint256 amount);
    event V2TokensWithdrawn(address indexed owner, uint256 amount);

    /**
     * @dev Constructor sets the addresses of both token contracts
     * @param _unaiV1 Address of the UNAI V1 token contract
     * @param _unaiV2 Address of the UNAI V2 token contract
     */
    constructor(address _unaiV1, address _unaiV2) Ownable(msg.sender) {
        require(_unaiV1 != address(0), "V1 address cannot be zero");
        require(_unaiV2 != address(0), "V2 address cannot be zero");
        require(_unaiV1 != _unaiV2, "V1 and V2 addresses must be different");

        unaiV1 = IERC20(_unaiV1);
        unaiV2 = IERC20(_unaiV2);
    }

    /**
     * @dev Allows users to migrate their V1 tokens to V2 tokens
     * @param amount The amount of tokens to migrate
     */
    function migrateTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(unaiV2.balanceOf(address(this)) >= amount, "Insufficient V2 tokens in contract");

        // Transfer V1 tokens from user to contract
        require(
            unaiV1.transferFrom(msg.sender, address(this), amount), "Failed to transfer V1 tokens"
        );

        // Transfer V2 tokens to user
        require(unaiV2.transfer(msg.sender, amount), "Failed to transfer V2 tokens");

        emit TokensMigrated(msg.sender, amount);
    }

    /**
     * @dev Allows owner to withdraw V1 tokens from the contract
     * @param amount Amount of V1 tokens to withdraw
     */
    function withdrawV1Tokens(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        require(unaiV1.balanceOf(address(this)) >= amount, "Insufficient V1 tokens in contract");

        require(unaiV1.transfer(owner(), amount), "Failed to transfer V1 tokens");

        emit V1TokensWithdrawn(owner(), amount);
    }

    /**
     * @dev Allows owner to withdraw V2 tokens from the contract
     * @param amount Amount of V2 tokens to withdraw
     */
    function withdrawV2Tokens(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        require(unaiV2.balanceOf(address(this)) >= amount, "Insufficient V2 tokens in contract");

        require(unaiV2.transfer(owner(), amount), "Failed to transfer V2 tokens");

        emit V2TokensWithdrawn(owner(), amount);
    }

    /**
     * @dev Returns the balance of V1 tokens in the contract
     */
    function getV1Balance() external view returns (uint256) {
        return unaiV1.balanceOf(address(this));
    }

    /**
     * @dev Returns the balance of V2 tokens in the contract
     */
    function getV2Balance() external view returns (uint256) {
        return unaiV2.balanceOf(address(this));
    }
}
