// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount} from "@aa/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "@aa/contracts/interfaces/PackedUserOperation.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "@aa/contracts/core/Helpers.sol";
import {IEntryPoint} from "@aa/contracts/interfaces/IEntryPoint.sol";

// Our minimal version of an EOA smart account with ERC-4337 contracts
contract MinimalAccount is IAccount, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error MinimalAccount__NotFromEntryPoint();
    error MinimalAccount__NotFromEntryPointOrOwner();
    error MinimalAccount__ExecutionFailed(bytes);
    error MinimalAccount__PrefundFailed(bytes);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IEntryPoint private immutable i_entryPoint;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier requireFromEntryPoint() {
        if (msg.sender != address(i_entryPoint)) {
            revert MinimalAccount__NotFromEntryPoint();
        }
        _;
    }

    modifier requireFromEntryPointOrOwner() {
        if (msg.sender != address(i_entryPoint) && msg.sender != owner()) {
            revert MinimalAccount__NotFromEntryPointOrOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address entryPoint) Ownable(msg.sender) {
        i_entryPoint = IEntryPoint(entryPoint);
    }

    // Accept funds in order to pay for transactions (since no paymaster)
    // Alt mempool will send txn, pull funds from here, and they are payed in _payPrefund, so we will need to be able to supply funds to this account to do so.
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // A simple execute function that allows the account to call arbitrary contracts
    function execute(address dest, uint256 value, bytes calldata functionData) external requireFromEntryPointOrOwner {
        (bool success, bytes memory result) = dest.call{value: value}(functionData);
        if (!success) {
            revert MinimalAccount__ExecutionFailed(result);
        }
    }

    // Entrypoint -> will call -> this function
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash, // EIP-191 version of the signed hash
        uint256 missingAccountFunds // Amount of ETH to pay the paymaster or entrypoint
    ) external requireFromEntryPoint returns (uint256 validationData) {
        // Validate the signature
        validationData = _validateSignature(userOp, userOpHash);

        // todo: (ideally) validate the nonce
        // _validateNonce(userOp)

        // Pay back to the EntryPoint for gas deposit
        _payPrefund(missingAccountFunds);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Validate the signature of the userOp. This can be any kind of custom validation.
    // For simplicity, we'll just validate if it's signed by the MinimalAccount contract owner.
    // userOpHash is EIP-191 version of the signed hash
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        // Convert from the incoming EIP-191 version of the signed hash back into a personal_sign message hash
        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        // This is so we can do an ECDSA recover on it. Who did this signing?
        address signer = ECDSA.recover(messageHash, userOp.signature);

        // Our verification logic
        // This could be anything, google session key, multi party sig, etc
        //
        // If it's not from the owner of this account...
        if (signer != owner()) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    // Pay the paymaster or entrypoint for gas deposit
    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds != 0) {
            (bool success, bytes memory _result) =
                payable(msg.sender).call{value: missingAccountFunds, gas: type(uint256).max}("");
            if (!success) {
                revert MinimalAccount__PrefundFailed(_result);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getEntryPoint() external view returns (address) {
        return address(i_entryPoint);
    }
}
