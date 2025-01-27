// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {UNAIMigration} from "../src/UNAIMigration.sol";
import {Contract as UNAI} from "../src/UNAI.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UNAIMigrationTest is Test {
    UNAIMigration public migration;
    UNAI public unaiV1;
    UNAI public unaiV2;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public operationsAddress = address(0x3);
    address public devAddress = address(0x4);

    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 1e18;

    function setUp() public {
        // Deploy V1 and V2 tokens
        unaiV1 = new UNAI(operationsAddress, devAddress);
        unaiV2 = new UNAI(operationsAddress, devAddress);

        // Deploy migration contract
        migration = new UNAIMigration(address(unaiV1), address(unaiV2));

        // Send V2 tokens to migration contract for users to claim
        unaiV2.transfer(address(migration), INITIAL_SUPPLY / 2);

        // Send V1 tokens to users for testing
        unaiV1.transfer(user1, 1000 * 1e18);
        unaiV1.transfer(user2, 1000 * 1e18);
    }

    function testConstructorValidation() public {
        // Test zero address validation
        vm.expectRevert("V1 address cannot be zero");
        new UNAIMigration(address(0), address(unaiV2));

        vm.expectRevert("V2 address cannot be zero");
        new UNAIMigration(address(unaiV1), address(0));

        // Test same address validation
        vm.expectRevert("V1 and V2 addresses must be different");
        new UNAIMigration(address(unaiV1), address(unaiV1));
    }

    function testMigrateTokens() public {
        uint256 amount = 100 * 1e18;
        uint256 initialV1Balance = unaiV1.balanceOf(user1);
        uint256 initialV2Balance = unaiV2.balanceOf(user1);

        // Approve migration contract to spend tokens
        vm.startPrank(user1);
        unaiV1.approve(address(migration), amount);

        // Migrate tokens
        migration.migrateTokens(amount);
        vm.stopPrank();

        // Check balances
        assertEq(unaiV1.balanceOf(user1), initialV1Balance - amount, "V1 balance not decreased");
        assertEq(unaiV2.balanceOf(user1), initialV2Balance + amount, "V2 balance not increased");
        assertEq(
            unaiV1.balanceOf(address(migration)), amount, "Migration contract V1 balance wrong"
        );
    }

    function test_RevertWhen_MigratingWithoutApproval() public {
        uint256 amount = 100 * 1e18;
        vm.startPrank(user1);
        // OpenZeppelin's ERC20 throws a custom error for insufficient allowance
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientAllowance(address,uint256,uint256)", address(migration), 0, amount
            )
        );
        migration.migrateTokens(amount);
        vm.stopPrank();
    }

    function test_RevertWhen_MigratingWithInsufficientV2Balance() public {
        uint256 amount = INITIAL_SUPPLY * 2; // More than available V2 tokens
        vm.startPrank(user1);
        unaiV1.approve(address(migration), amount);
        vm.expectRevert("Insufficient V2 tokens in contract");
        migration.migrateTokens(amount);
        vm.stopPrank();
    }

    function testWithdrawV1Tokens() public {
        // First do a migration to get some V1 tokens in the contract
        uint256 amount = 100 * 1e18;
        vm.startPrank(user1);
        unaiV1.approve(address(migration), amount);
        migration.migrateTokens(amount);
        vm.stopPrank();

        uint256 initialOwnerV1Balance = unaiV1.balanceOf(owner);

        // Withdraw V1 tokens
        migration.withdrawV1Tokens(amount);

        assertEq(
            unaiV1.balanceOf(owner),
            initialOwnerV1Balance + amount,
            "Owner V1 balance not increased"
        );
        assertEq(unaiV1.balanceOf(address(migration)), 0, "Migration contract V1 balance not zero");
    }

    function testWithdrawV2Tokens() public {
        uint256 amount = 100 * 1e18;
        uint256 initialOwnerV2Balance = unaiV2.balanceOf(owner);

        // Withdraw V2 tokens
        migration.withdrawV2Tokens(amount);

        assertEq(
            unaiV2.balanceOf(owner),
            initialOwnerV2Balance + amount,
            "Owner V2 balance not increased"
        );
    }

    function test_RevertWhen_NonOwnerWithdrawsV1Tokens() public {
        vm.startPrank(user1);
        // OpenZeppelin's Ownable throws a custom error for unauthorized access
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        migration.withdrawV1Tokens(100 * 1e18);
        vm.stopPrank();
    }

    function test_RevertWhen_NonOwnerWithdrawsV2Tokens() public {
        vm.startPrank(user1);
        // OpenZeppelin's Ownable throws a custom error for unauthorized access
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        migration.withdrawV2Tokens(100 * 1e18);
        vm.stopPrank();
    }

    function testGetBalances() public {
        uint256 amount = 100 * 1e18;

        // Initial V2 balance should match what we sent in setup
        assertEq(migration.getV2Balance(), INITIAL_SUPPLY / 2, "Initial V2 balance incorrect");

        // Do a migration
        vm.startPrank(user1);
        unaiV1.approve(address(migration), amount);
        migration.migrateTokens(amount);
        vm.stopPrank();

        // Check balances
        assertEq(migration.getV1Balance(), amount, "V1 balance incorrect after migration");
        assertEq(
            migration.getV2Balance(),
            (INITIAL_SUPPLY / 2) - amount,
            "V2 balance incorrect after migration"
        );
    }

    function testPauseAndUnpause() public {
        // Test pause
        migration.pause();
        assertTrue(migration.paused(), "Contract should be paused");

        // Test unpause
        migration.unpause();
        assertFalse(migration.paused(), "Contract should be unpaused");
    }

    function test_RevertWhen_NonOwnerPauses() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        migration.pause();
        vm.stopPrank();
    }

    function test_RevertWhen_NonOwnerUnpauses() public {
        migration.pause(); // Owner pauses

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        migration.unpause();
        vm.stopPrank();
    }

    function test_RevertWhen_MigratingWhilePaused() public {
        uint256 amount = 100 * 1e18;

        // Setup approval
        vm.startPrank(user1);
        unaiV1.approve(address(migration), amount);

        // Pause migration
        vm.stopPrank();
        migration.pause();

        // Try to migrate while paused
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        migration.migrateTokens(amount);
        vm.stopPrank();
    }

    function testWithdrawWhilePaused() public {
        uint256 amount = 100 * 1e18;

        // First do a migration to get some V1 tokens in the contract
        vm.startPrank(user1);
        unaiV1.approve(address(migration), amount);
        migration.migrateTokens(amount);
        vm.stopPrank();

        // Pause the contract
        migration.pause();

        // Owner should still be able to withdraw while paused
        uint256 initialOwnerV1Balance = unaiV1.balanceOf(owner);
        migration.withdrawV1Tokens(amount);

        assertEq(
            unaiV1.balanceOf(owner),
            initialOwnerV1Balance + amount,
            "Owner V1 balance not increased while paused"
        );
    }

    function testReentrancyProtection() public {
        // Deploy malicious token that tries to reenter
        MaliciousToken maliciousV1 = new MaliciousToken();
        UNAIMigration vulnerableMigration = new UNAIMigration(address(maliciousV1), address(unaiV2));

        // Send V2 tokens to migration contract
        unaiV2.transfer(address(vulnerableMigration), 1000 * 1e18);

        // Try to migrate with malicious token
        vm.expectRevert();
        maliciousV1.attackMigration(address(vulnerableMigration), 100 * 1e18);
    }
}

// Helper contract to test reentrancy protection
contract MaliciousToken {
    UNAIMigration public migration;
    uint256 public attackAmount;
    uint256 public counter;

    function attackMigration(address _migration, uint256 _amount) external {
        migration = UNAIMigration(_migration);
        attackAmount = _amount;
        migration.migrateTokens(_amount);
    }

    function transferFrom(address, address, uint256) external returns (bool) {
        if (counter == 0) {
            counter++;
            migration.migrateTokens(attackAmount); // Try to reenter
        }
        return true;
    }

    function balanceOf(address) external pure returns (uint256) {
        return type(uint256).max; // Pretend we have infinite balance
    }
}
