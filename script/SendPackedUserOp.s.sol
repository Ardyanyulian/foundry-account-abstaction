// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol"; 
import {HelperConfig} from "script/HelperConfig.s.sol"; 
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {MinimalAccount}  from "../../src/ethereum/MinimalAccount.sol";

using MessageHashUtils for bytes32;

contract SendPackedUserOp is Script {

    HelperConfig internal helperConfig; 
    MinimalAccount internal minimalAccount;
    // Constant Variables
    // Private Key Anvil Default Account
    uint256 constant ANVIL_DEFAULT_KEY;
    
    
    function setUp() public {
        helperConfig = new HelperConfig();
    }

    // Fungsi setter untuk MinimalAccountTest (Fixes previous errors)
    function setHelperConfig(HelperConfig config) public {
        helperConfig = config;
    }
    
    // PERBAIKAN: Nonce disetel 0 karena ini adalah UserOp pertama dan initCode kosong di test.
    function generateSignedUserOperation(bytes memory callData, HelperConfig.NetworkConfig memory config, address _minimalAccount)
        public
        view 
        returns (PackedUserOperation memory)
    {
        
        // 1. Nonce UserOp pertama HARUS 0 karena MinimalAccount baru di-deploy di setUp
        // Nonce AA berbeda dengan nonce EOA
        uint256 nonce = vm.getNonce(_minimalAccount) - 1; 

        PackedUserOperation memory userOp = _generateUnsignedUserOperation(
            callData,
            _minimalAccount, // sender adalah EOA yang meniru Account
            nonce
        );
    
        // 2. Hitung UserOp Hash
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(userOp);
        bytes32 digest = userOpHash.toEthSignedMessageHash(); 
    
        uint8 v;
        bytes32 r;
        bytes32 s;
    
        if (block.chainid == 31337) {
            // Menggunakan Private Key Anvil
            (v, r, s) = vm.sign(ANVIL_DEFAULT_KEY, digest);
        } else { 
            // Menggunakan Private Key EOA
            (v, r, s) = vm.sign(config.account, digest);
        }
        
        // 3. Penanganan V-Value Mutlak
        // vm.sign mungkin mengembalikan v=0 atau v=1. ECDSA.recover OpenZeppelin membutuhkan v=27 atau v=28.
        if (v <= 1) { 
            v += 27;
        }

        userOp.signature = abi.encodePacked(r, s, v); 
        return userOp;
    }


    // Helper function to populate the UserOperation fields (excluding signature)
    function _generateUnsignedUserOperation(
        bytes memory callData,
        address sender,
        uint256 nonce
    ) internal pure returns (PackedUserOperation memory) {
        
        uint256 verificationGasLimit = 200000;
        uint256 callGasLimit = 300000;
        uint256 maxFeePerGas = 100 gwei;
        uint256 maxPriorityFeePerGas = 2 gwei;

        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: hex"",
            callData: callData,
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | callGasLimit),
            preVerificationGas: verificationGasLimit + 50000,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | maxFeePerGas),
            paymasterAndData: hex"",
            signature: hex""
        });
    }
}