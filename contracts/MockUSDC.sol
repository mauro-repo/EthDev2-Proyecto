// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC
/// @notice Token ERC-20 que simula ser una stablecoin para pagos de alquiler.
contract MockUSDC is ERC20 {
    /// @notice Constructor que mintea 1 millón de tokens al deployer.
    constructor() ERC20("Mock USDC", "mUSDC") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }
}