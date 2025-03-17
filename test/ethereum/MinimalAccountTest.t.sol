// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/Script.sol";
import {PackedUserOperation} from "@aa/contracts/interfaces/PackedUserOperation.sol";
import {MinimalAccount} from "../../src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployMinimalAccount} from "../../script/DeployMinimalAccount.s.sol";
import {SendPackedUserOp} from "../../script/SendPackedUserOp.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IEntryPoint} from "@aa/contracts/interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MinimalAccountTest is Test {
    using MessageHashUtils for bytes32;

    DeployMinimalAccount deployer;
    HelperConfig helperConfig;
    MinimalAccount minimalAccount;
    ERC20Mock usdc;
    SendPackedUserOp sendPackedUserOp;

    address RANDOM_USER = makeAddr("RANDOM_USER");
    uint256 MINT_AMOUNT = 1e18;

    function setUp() public {
        deployer = new DeployMinimalAccount();
        (helperConfig, minimalAccount) = deployer.deployMinimalAccount();
        usdc = new ERC20Mock();
        sendPackedUserOp = new SendPackedUserOp();
    }

    // Test USDC Approval
    // Approve USDC amount, but should come `from` the EntryPoint as the msg.sender
    function testOwnerCanExecuteCalls() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), MINT_AMOUNT);

        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, functionData);

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), MINT_AMOUNT);
    }

    function testNonOwnerCannotExecuteCalls() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), MINT_AMOUNT);

        // Act
        vm.prank(RANDOM_USER);

        // Assert
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData);
    }

    // Test we can sign correctly
    function testRecoverSignedOp() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), MINT_AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory userOp =
            sendPackedUserOp.generateSignedUserOperation(executeCallData, helperConfig.getConfig(), address(minimalAccount));
        bytes32 userOpHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(userOp);

        // Act
        address actualSigner = ECDSA.recover(userOpHash.toEthSignedMessageHash(), userOp.signature);

        // Assert
        assertEq(actualSigner, minimalAccount.owner());
    }

    // 1. Sign user ops
    // 2. Call validation
    // 3. Assert return is correct
    function testValidationOfUserOps() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), MINT_AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory userOp =
            sendPackedUserOp.generateSignedUserOperation(executeCallData, helperConfig.getConfig(), address(minimalAccount));
        bytes32 userOpHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(userOp);
        uint256 missingAccountFunds = 1e18;
        vm.deal(address(minimalAccount), missingAccountFunds);

        // Act
        vm.prank(helperConfig.getConfig().entryPoint);
        uint256 validationData = minimalAccount.validateUserOp(userOp, userOpHash, missingAccountFunds);

        // Assert - we simply return 0 for success and 1 for failure (SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS)
        assertEq(validationData, 0);
    }

    function testEntryPointCanExecuteCalls() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), MINT_AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory userOp =
            sendPackedUserOp.generateSignedUserOperation(executeCallData, helperConfig.getConfig(), address(minimalAccount));
        vm.deal(address(minimalAccount), 1e18);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Act - anyone can send the signed transaction, they get the fees for sending it
        vm.prank(RANDOM_USER);
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(RANDOM_USER));

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), MINT_AMOUNT);
    }
}
