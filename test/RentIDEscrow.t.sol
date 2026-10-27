// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/MockUSDC.sol";
import "../contracts/RentIDReputation.sol";
import "../contracts/RentIDEscrow.sol";

contract RentIDEscrowTest is Test {
    MockUSDC public usdc;
    RentIDReputation public reputation;
    RentIDEscrow public escrow;

    address public landlord;
    address public tenant;

    uint256 public constant RENT_AMOUNT = 1000 * 10 ** 6; // 1000 mUSDC
    uint256 public constant DEPOSIT_AMOUNT = 2000 * 10 ** 6; // 2000 mUSDC

    function setUp() public {
        // 1. Configurar actores simulados (como en Remix, pero con Foundry)
        landlord = makeAddr("landlord");
        tenant = makeAddr("tenant");

        // 2. Deployar contratos (El test es el admin)
        usdc = new MockUSDC();
        reputation = new RentIDReputation();
        escrow = new RentIDEscrow(address(usdc), address(reputation));
        
        // 3. Dar permisos al Escrow para mintear NFTs de reputación
        reputation.grantRole(reputation.MINTER_ROLE(), address(escrow));
        
        // 4. Dar rol de Landlord al landlord
        escrow.grantRole(escrow.LANDLORD_ROLE(), landlord);

        // 5. Fondear al inquilino con USDC (10,000) y darle approve al Escrow
        usdc.transfer(tenant, 10_000 * 10 ** 6); 
        vm.prank(tenant);
        usdc.approve(address(escrow), type(uint256).max);
    }

    /// @notice Test del flujo exitoso: Crear contrato, viajar en el tiempo y pagar.
    function test_Flow_CreateAndPayRent() public {
        // 1. Landlord crea el contrato
        vm.prank(landlord);
        escrow.createAgreement(tenant, RENT_AMOUNT, DEPOSIT_AMOUNT);
        
        uint256 agreementId = 0;
        // Verificar que el contrato se creó correctamente
        (address _landlord, address _tenant, uint256 _rent, , , , bool _isActive) = escrow.agreements(agreementId);
        assertEq(_landlord, landlord);
        assertEq(_tenant, tenant);
        assertEq(_rent, RENT_AMOUNT);
        assertTrue(_isActive);

        // 2. Viajar en el tiempo 31 días (Para que el pago esté habilitado)
        // Esto es clave para simular el paso de un mes en la blockchain
        vm.warp(block.timestamp + 31 days);

        // 3. Inquilino paga el alquiler
        uint256 landlordBalanceBefore = usdc.balanceOf(landlord);
        
        vm.prank(tenant);
        escrow.payRent(agreementId);

        // 4. Verificaciones
        uint256 landlordBalanceAfter = usdc.balanceOf(landlord);
        assertEq(landlordBalanceAfter - landlordBalanceBefore, RENT_AMOUNT, "Landlord should receive rent");
        
        // Verificar que el inquilino recibió el NFT Soulbound
        assertEq(reputation.balanceOf(tenant), 1, "Tenant should have 1 SBT");
        assertEq(reputation.ownerOf(1), tenant, "Tenant should own token 1");
    }

    /// @notice Test de error: Intentar pagar antes de que pase el mes.
    function test_RevertWhen_PayingTooEarly() public {
        vm.prank(landlord);
        escrow.createAgreement(tenant, RENT_AMOUNT, DEPOSIT_AMOUNT);

        // Intentar pagar inmediatamente (sin viajar en el tiempo)
        vm.prank(tenant);
        vm.expectRevert(RentIDEscrow.RentNotDueYet.selector);
        escrow.payRent(0);
    }

    /// @notice Test de Seguridad: Intentar transferir el SBT (debe fallar).
    function test_RevertWhen_TransferringSBT() public {
        // Creamos el alquiler y pagamos para que el inquilino tenga el NFT
        vm.prank(landlord);
        escrow.createAgreement(tenant, RENT_AMOUNT, DEPOSIT_AMOUNT);
        vm.warp(block.timestamp + 31 days);
        vm.prank(tenant);
        escrow.payRent(0);

        // El inquilino intenta transferir el NFT a otra dirección
        address hacker = makeAddr("hacker");
        vm.prank(tenant);
        vm.expectRevert(RentIDReputation.SBTNotTransferable.selector);
        reputation.transferFrom(tenant, hacker, 1); // TokenId 1
    }

    /// @notice Test de error: Un tercero intenta pagar por el inquilino.
    function test_RevertWhen_NotTenantPays() public {
        vm.prank(landlord);
        escrow.createAgreement(tenant, RENT_AMOUNT, DEPOSIT_AMOUNT);
        vm.warp(block.timestamp + 31 days);

        address hacker = makeAddr("hacker");
        usdc.transfer(hacker, 5000 * 10 ** 6);
        
        vm.startPrank(hacker);
        usdc.approve(address(escrow), type(uint256).max);
        vm.expectRevert(RentIDEscrow.NotTenant.selector);
        escrow.payRent(0);
        vm.stopPrank();
    }

    /// @notice FUZZ TESTING: Probar que el pago funciona con cualquier monto válido.
    function testFuzz_PayRent(uint256 rentAmount, uint256 depositAmount) public {
        // 1. Limitar los valores a rangos realistas (50-500 USDC alquiler, 100-1000 USDC depósito)
        rentAmount = bound(rentAmount, 50 * 10**6, 500 * 10**6);
        depositAmount = bound(depositAmount, 100 * 10**6, 1000 * 10**6);

        // 2. Fondear al inquilino DENTRO del test con lo necesario (garantiza saldo suficiente)
        uint256 totalNeeded = 2 * rentAmount + depositAmount;
        usdc.transfer(tenant, totalNeeded);

        // 3. Aprobar al Escrow (por si el approve del setUp no cubrió el monto)
        vm.prank(tenant);
        usdc.approve(address(escrow), type(uint256).max);

        // 4. Ejecutar el flujo normal del alquiler
        vm.prank(landlord);
        escrow.createAgreement(tenant, rentAmount, depositAmount);

        vm.warp(block.timestamp + 31 days);

        vm.prank(tenant);
        escrow.payRent(0);

        // 5. Verificar que el NFT de reputación se minteó
        assertEq(reputation.balanceOf(tenant), 1);
    }
}