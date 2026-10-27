// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title RentIDReputation
/// @notice NFT no transferible (Soulbound) que prueba el historial de pagos de un inquilino.
contract RentIDReputation is ERC721, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 private _nextTokenId;

    /// @notice Error lanzado si se intenta transferir el SBT.
    error SBTNotTransferable();

    /// @notice Constructor inicializa el nombre, símbolo y roles.
    constructor() ERC721("RentID Reputation", "RID") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Emite una nueva insignia de reputación.
    /// @dev Solo el contrato Escrow (con MINTER_ROLE) puede llamar a esta función.
    /// @param to Dirección del inquilino que recibe la insignia.
    /// @return tokenId El ID del NFT recién minteado.
    function mintReputation(address to) external onlyRole(MINTER_ROLE) returns (uint256) {
        _nextTokenId++;
        uint256 newTokenId = _nextTokenId;
        _safeMint(to, newTokenId);
        return newTokenId;
    }

    /// @dev Sobrescritura para bloquear transferencias. Si 'from' no es cero (mint) y 'to' no es cero (burn), revierte.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert SBTNotTransferable();
        }
        return super._update(to, tokenId, auth);
    }

    /// @dev Requerido por Solidity por la herencia múltiple.
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}