// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol"; // Adjust path as needed
import {HelperConfig} from "./HelperConfig.s.sol"; // Relative path to HelperConfig

contract DeployMinimal is Script {
    HelperConfig helperConfig;
    MinimalAccount minimalAccount;

    function run() public returns (HelperConfig, MinimalAccount) {
        helperConfig = new HelperConfig(); 
        return deployMinimalAccount();
    }


    function deployMinimalAccount() public returns (HelperConfig helperConfigInstance, MinimalAccount minimalAccountContract) {
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.account); // Use the burner wallet from config for broadcasting

        minimalAccount = new MinimalAccount(config.entryPoint);

        // The MinimalAccount constructor (if Ownable) might set config.account as owner if it's the broadcaster.
        // This explicit transfer ensures the script runner (msg.sender in script context) becomes the owner,
        // or reaffirms ownership if config.account == msg.sender.
        // It's often good practice for clarity and to ensure the intended final owner.
        minimalAccount.transferOwnership(config.account);
        
        vm.stopBroadcast();
        
        return (helperConfig, minimalAccount);
    }

    
}