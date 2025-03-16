// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount} from "../../src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployMinimalAccount} from "../../script/DeployMinimalAccount.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract MinimalAccountTest is Test {
    DeployMinimalAccount deployer;
    HelperConfig helperConfig;
    MinimalAccount minimalAccount;
    ERC20Mock usdc;

    address RANDOM_USER = makeAddr("RANDOM_USER");
    uint256 MINT_AMOUNT = 1e18;

    function setUp() public {
        deployer = new DeployMinimalAccount();
        (helperConfig, minimalAccount) = deployer.deployMinimalAccount();
        usdc = new ERC20Mock();
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
}
