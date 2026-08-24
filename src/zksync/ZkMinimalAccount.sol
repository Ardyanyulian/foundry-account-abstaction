// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";

// The Transaction struct is defined within or alongside system contract interfaces.
// For direct use as per IAccount, ensure the path correctly resolves to its definition.
// The video lesson points to the struct being available via an import like this:

import {Transaction,MemoryTransactionHelper} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {DEPLOYER_SYSTEM_CONTRACT, BOOTLOADER_FORMAL_ADDRESS, NONCE_HOLDER_SYSTEM_CONTRACT} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {Utils} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;
    
    error ZkMinimalAccount__NotFromBootloader();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__FailedToPay();
    error ZkMinimalAccount__NotFromBootloaderOrOwner();
    error ZkMinimalAccount_InvalidSignature();
    error ZkMinimalAccount_NotEnoughBalance();
    
    // Magic value to be returned by validateTransaction on success
    // bytes4(keccak256("isValidSignature(bytes32,bytes)")
    // bytes4 constant PT_MAGIC_VALUE = 0x1626ba7e; // Example, actual value might differ based on system specifics
    
    // TODO: Implement owner state variable and constructor
    constructor () Ownable(msg.sender) {}


    /**
    * Phase 1 Validation
    * 1. The user sends the transaction to the "zkSync API client" (sort of a "light node")
    * ...
    */

   // Modifier
   modifier requireFromBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) { // Check caller
            revert ZkMinimalAccount__NotFromBootloader(); // Custom error
        }
        _; // Proceed if check passes
    }


    modifier requireFromBootloaderOrOwner() {
        // Allow calls only from the official Bootloader address or the account's owner.
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkMinimalAccount__NotFromBootloaderOrOwner();
        }
        _; // Proceed with function execution if the check passes
    }


    // Digunakan untuk memvalidasi address bootloader
    // Memastikan account mempunyai biaya untuk mencover biaya dari transaksi
    // return magic byte4
    // harus menincrementkan akun yang berhasil divalidasi untuk mencegah replay attack
    // Pastikan dibuatkan modifier agar tidak bisa di panggil secara arbitrary
    function validateTransaction(
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    ) external payable requireFromBootloader returns (bytes4 magic) {
        return _validateTransaction(_transaction);
    }

    /**
    * Phase 1 Validation
    * ...
    * 2. The zkSync API client checks to see the nonce is unique by querying the
    *    NonceHolder system contract
    * ...
    */


    // Digunakan untuk mengeksekusi transaksi yang datang
    // parameter _txHash dan _suggestedSignedHash  mungkin sedikit advance bisa di ignorekan 
    function executeTransaction(
        bytes32 /*_txHash*/,
        bytes32 /*_suggestedSignedHash*/,
        Transaction calldata _transaction
    ) external payable override {
        _executeTransaction(_transaction);
        
        
    }

    // Digunakan untuk mengeksekusi transaksi yang dipanggil oleh kontrak lain bisanya untuk mevalidasi saja
    function executeTransactionFromOutside(Transaction calldata _transaction) external payable override {
        bytes4 magic = _validateTransaction(_transaction);
        // IMPORTANT: Always check the result of validation.
        // If the signature is not valid, or other validation checks fail,
        // _validateTransaction will return a magic value other than ACCOUNT_VALIDATION_SUCCESS_MAGIC.
        if (magic != ACCOUNT_VALIDATION_SUCCESS_MAGIC) {
            revert ZkMinimalAccount_InvalidSignature(); // Or a more generic validation failed error
        }
        _executeTransaction(_transaction);
    }

    // Digunakan untuk membayar traksaksi yang telah di eksekusi
    // Dipanggil secara langsung ketika akun tersebut yang langsung membayar
    
    function payForTransaction(
        bytes32 /*_txHash8*/,
        bytes32 /*_suggestedSignedHash*/,
        Transaction calldata _transaction
    ) external payable override {
         // In this minimal implementation, we can ignore _txHash and _suggestedSignedHash.
        // All necessary information for payment is contained within the _transaction struct.

        // The core logic relies on a helper function, payToTheBootloader,
        // which is part of the TransactionHelper library (via _transaction).
        
        // Fungsi dari _transaction.payToTheBootloader()
        // memberikan alamat dari bootloader
        // mengkalkulasi bayaknya yang harus dibayar
        // mengeksekusi payments menggunakan bahasa low level / assembly code 
        bool success = _transaction.payToTheBootloader();

        // If the payment to the bootloader fails, revert the transaction.
        if (!success) {
            revert ZkMinimalAccount__FailedToPay();
        }
    }


    // Digunakan untuk mengatur biaya pembayaran 
    // Dipanggil untuk mensponsori transaksi dan itu menghandle inisasi transaksi dan persiapan yang diperlukan oleh paymaster
    function prepareForPaymaster(
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    ) external payable override {
        // TODO: Logic for preparing the transaction for a paymaster
        revert("Not implemented"); // Placeholder
    }

    // INTERNAL FUNCTION
   function _validateTransaction(Transaction memory _transaction) internal returns (bytes4 magic) {
        // To prevent "stack too deep" errors, we "flatten" the transaction struct at the beginning.
        // We extract all necessary fields into local variables and use them instead of repeatedly
        // accessing the complex `_transaction` memory struct. This significantly reduces stack pressure.
        uint256 nonce = _transaction.nonce;
        uint256 requiredBalance = _transaction.totalRequiredBalance();
        bytes memory signature = _transaction.signature;
    
        // Pre-compute the encoded hash input
        bytes32  encodedHash = _transaction.encodeHash();
    
        // Compute the final hash
        bytes32  txHash = MessageHashUtils.toEthSignedMessageHash(encodedHash);

        {
            // Scope 1: Validate signature
            address signer = _recoverSigner(txHash, signature);
            if (signer != owner()) {
               return bytes4(0); // Return early if signature is invalid
            }
        }

        {
            // Scope 2: Validate balance and nonce

            // Revalidate the signature

            if (requiredBalance > address(this).balance) {
                revert ZkMinimalAccount_NotEnoughBalance();
            }
            _callNonceHolder(nonce);
        }
        return ACCOUNT_VALIDATION_SUCCESS_MAGIC;
    }

    function _callNonceHolder(uint256 _nonce) internal {
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()), // Kembalikan ke pemanggilan langsung
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_nonce))
        );
    }

    function _recoverSigner(bytes32 _hash, bytes memory _signature) internal pure returns (address) {
        // This function is now 'pure' as it only operates on its inputs, making it more optimized.
        return ECDSA.recover(_hash, _signature); 
    }  

    function _executeTransaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;
    
        // Handle calls to the DEPLOYER_SYSTEM_CONTRACT for contract deployments
        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            // Standard external call
            bool success;
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if (!success) {
                revert ZkMinimalAccount__ExecutionFailed();
            }
        }
    } 


    // TODO: Implement fallback/receive functions if needed for ETH transfers
    receive() external payable {}

}