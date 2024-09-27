// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "../src/UNAI.sol";

contract Burn is Script {
    IERC20 public lpToken;
    uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_PRIVATE_KEY"));
    address deployer = vm.envAddress("DEPLOYER_ADDRESS");

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // Assuming the token contract is already deployed, provide its address here
        lpToken = IERC20(0xe7B52694d6ca01701F04DD1FD2AA40e9f2105Bf5); // Replace with your actual token contract address

        // get the balance of the deployer
        uint256 balance = lpToken.balanceOf(deployer);

        // approve the contract to spend the tokens
        lpToken.approve(address(this), balance);

        // Burn the tokens (ensure the burn function exists in your token contract)
        lpToken.transferFrom(deployer, address(0x000000000000000000000000000000000000dEaD), balance);
        console.log("Burned", balance, "tokens from deployer", deployer);

        vm.stopBroadcast();
    }
}
