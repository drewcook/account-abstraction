// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployMinimalAccount is Script {
    function run() external {}

    function deployMinimalAccount() public returns (HelperConfig helperConfig, MinimalAccount minimalAccount) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.account);
        minimalAccount = new MinimalAccount(config.entryPoint);
        // Doubly ensure that ownership is to the deployer, in this case the config.account
        minimalAccount.transferOwnership(config.account);
        vm.stopBroadcast();

        return (helperConfig, minimalAccount);
    }
}
