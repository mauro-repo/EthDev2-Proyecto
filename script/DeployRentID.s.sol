// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/MockUSDC.sol";
import "../contracts/RentIDReputation.sol";
import "../contracts/RentIDEscrow.sol";

contract DeployRentID is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockUSDC usdc = new MockUSDC();
        RentIDReputation reputation = new RentIDReputation();
        RentIDEscrow escrow = new RentIDEscrow(address(usdc), address(reputation));

        reputation.grantRole(reputation.MINTER_ROLE(), address(escrow));

        vm.stopBroadcast();
    }
}