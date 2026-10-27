// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./RentIDReputation.sol";

/// @title RentIDEscrow
/// @notice Gestiona contratos de alquiler, cobra pagos y emite reputación.
contract RentIDEscrow is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable paymentToken;
    RentIDReputation public immutable reputationSBT;

    bytes32 public constant LANDLORD_ROLE = keccak256("LANDLORD_ROLE");

    /// @notice Estructura que define un contrato de alquiler.
    struct RentalAgreement {
        address landlord;
        address tenant;
        uint256 monthlyRent;
        uint256 depositAmount;
        uint256 nextPaymentDue;
        uint256 monthsPaid;
        bool isActive;
    }

    /// @notice Mapeo de ID de alquiler a la estructura.
    mapping(uint256 => RentalAgreement) public agreements;
    uint256 public nextAgreementId;

    // --- Eventos ---
    event AgreementCreated(uint256 indexed agreementId, address indexed landlord, address indexed tenant, uint256 rent);
    event RentPaid(uint256 indexed agreementId, address indexed tenant, uint256 amount, uint256 reputationTokenId);
    event DepositRefunded(uint256 indexed agreementId, address indexed tenant, uint256 amount);

    // --- Custom Errors ---
    error InvalidAmount();
    error NotTenant();
    error NotLandlord();
    error RentNotDueYet();
    error AgreementNotActive();

    /// @notice Inicializa el contrato.
    /// @param _paymentToken Dirección del ERC-20 (MockUSDC).
    /// @param _reputationSBT Dirección del contrato de reputación.
    constructor(address _paymentToken, address _reputationSBT) {
        paymentToken = IERC20(_paymentToken);
        reputationSBT = RentIDReputation(_reputationSBT);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LANDLORD_ROLE, msg.sender);
    }

    /// @notice Crea un contrato de alquiler y cobra la garantía + primer mes.
    /// @param _tenant Dirección del inquilino.
    /// @param _monthlyRent Monto del alquiler mensual.
    /// @param _depositAmount Monto del depósito de garantía.
    function createAgreement(address _tenant, uint256 _monthlyRent, uint256 _depositAmount) external onlyRole(LANDLORD_ROLE) {
        if (_monthlyRent == 0 || _depositAmount == 0) revert InvalidAmount();
        
        uint256 agreementId = nextAgreementId++;
        agreements[agreementId] = RentalAgreement({
            landlord: msg.sender,
            tenant: _tenant,
            monthlyRent: _monthlyRent,
            depositAmount: _depositAmount,
            nextPaymentDue: block.timestamp + 1 minutes,
            monthsPaid: 0,
            isActive: true
        });

        // El inquilino deposita la garantía y el primer mes
        uint256 totalToPay = _monthlyRent + _depositAmount;
        paymentToken.safeTransferFrom(_tenant, address(this), totalToPay);

        emit AgreementCreated(agreementId, msg.sender, _tenant, _monthlyRent);
    }

    /// @notice Permite al inquilino pagar el alquiler y ganar reputación.
    /// @param _agreementId ID del contrato de alquiler.
    function payRent(uint256 _agreementId) external nonReentrant {
        RentalAgreement storage agreement = agreements[_agreementId];
        
        // 1. Checks
        if (!agreement.isActive) revert AgreementNotActive();
        if (msg.sender != agreement.tenant) revert NotTenant();
        if (block.timestamp < agreement.nextPaymentDue) revert RentNotDueYet();

        // 2. Effects
        agreement.monthsPaid++;
        agreement.nextPaymentDue += 30 days;
        
        // Interacción con el contrato de reputación
        uint256 repTokenId = reputationSBT.mintReputation(msg.sender);

        // 3. Interactions
        paymentToken.safeTransferFrom(msg.sender, agreement.landlord, agreement.monthlyRent);

        emit RentPaid(_agreementId, msg.sender, agreement.monthlyRent, repTokenId);
    }

    /// @notice Finaliza el contrato y devuelve el depósito.
    /// @param _agreementId ID del contrato de alquiler.
    function endAgreement(uint256 _agreementId) external nonReentrant {
        RentalAgreement storage agreement = agreements[_agreementId];
        
        // 1. Checks
        if (!agreement.isActive) revert AgreementNotActive();
        if (msg.sender != agreement.landlord) revert NotLandlord();

        // 2. Effects
        agreement.isActive = false;
        uint256 depositToRefund = agreement.depositAmount;
        agreement.depositAmount = 0; // Previene reentrancy

        // 3. Interactions
        paymentToken.safeTransfer(agreement.tenant, depositToRefund);

        emit DepositRefunded(_agreementId, agreement.tenant, depositToRefund);
    }
}