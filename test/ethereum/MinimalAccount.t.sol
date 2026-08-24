// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOp, PackedUserOperation} from "../../script/SendPackedUserOp.s.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {console, console2} from "../../lib/forge-std/src/Script.sol";


contract MinimalAccountTest is Test {
    using MessageHashUtils for bytes32;

    // DEKLARASI STATE VARIABLES
    SendPackedUserOp sendPackedUserOpScript;
    HelperConfig helperConfig; 
    HelperConfig.NetworkConfig activeNetworkConfig;
    MinimalAccount minimalAccount;
    ERC20Mock usdc;
    
    uint256 constant AMOUNT = 1e18;
    address randomUser = makeAddr("randomUser");
    address owner; // EOA owner of minimalAccount

    function setUp() public {

        sendPackedUserOpScript = new SendPackedUserOp(); 
        helperConfig = new HelperConfig();
        
        sendPackedUserOpScript.setHelperConfig(helperConfig); 
        
        activeNetworkConfig = helperConfig.getOrCreateAnvilEthConfig();
        
        // PERBAIKAN: Gunakan USDC yang di-deploy di HelperConfig
        usdc = ERC20Mock(activeNetworkConfig.usdc); 
        
        // Deploy MinimalAccount
        owner = activeNetworkConfig.account; 
        vm.prank(owner);
        minimalAccount = new MinimalAccount(activeNetworkConfig.entryPoint);
    }


    function testOwnerCanExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        
        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, functionData);

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }


    function testNonOwnerCannotExecuteCommands() public {
        // Arrange
        address dest = address(usdc);
        uint256 value = 0;
        
        
        bytes memory functionData = abi.encodeWithSelector(
            ERC20Mock.mint.selector,
            address(minimalAccount),
            AMOUNT
        );
    
        // Act & Assert
        vm.prank(randomUser); 

        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData); 
    }


    function testRecoverSignedOp() public {
        // Arrange:

        // 1. Define the target call data 
        bytes memory functionDataForUSDCMint = abi.encodeWithSelector(
            usdc.mint.selector,
            address(minimalAccount), 
            AMOUNT
        );

        // 2. Define the callData for MinimalAccount.execute
        bytes memory executeCallData = abi.encodeWithSelector(
            minimalAccount.execute.selector,
            address(usdc), 
            0, 
            functionDataForUSDCMint 
        );

        // 3. Generate the signed PackedUserOperation
        PackedUserOperation memory packedUserOp = sendPackedUserOpScript.generateSignedUserOperation(
            executeCallData,
            activeNetworkConfig,
            address(minimalAccount) 
        );
        
        // 4. Get the userOpHash again
        bytes32 userOperationHash = IEntryPoint(activeNetworkConfig.entryPoint)
            .getUserOpHash(packedUserOp);
        
        // Act:
        address actualSigner = ECDSA.recover(
            userOperationHash.toEthSignedMessageHash(), 
            packedUserOp.signature
        );

        
        // Assert:
        assertEq(actualSigner, minimalAccount.owner(), "Signer recovery failed");
    }

    function testValidationOfUserOps() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);

        PackedUserOperation memory packedUserOp =
            sendPackedUserOpScript.generateSignedUserOperation(executeCallData, helperConfig.getConfig(), address(minimalAccount)); 

        bytes32 userOperationHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);

        uint256 missingAccountFunds = 1e18;

        // Act
        vm.prank(address(helperConfig.getConfig().entryPoint));
        uint256 validationData = minimalAccount.validateUserOp(
            packedUserOp,
            userOperationHash,
            missingAccountFunds
        );
            // Assert
        assertEq(validationData, 0);
    }

    function testEntryPointCanExecuteCommands() public{
        // Assert initial state
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        
        // Address yang dituju dan juga value awal
        address dest = address(usdc);
        uint256 value = 0;

        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData = abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        
        PackedUserOperation memory packedUserOp = sendPackedUserOpScript.generateSignedUserOperation(
            executeCallData,
            helperConfig.getConfig(),
            address(minimalAccount)
        );

        // Act
        vm.deal(address(minimalAccount), 1e18); // Deals 1 ETH to minimalAccount
        
        // console.log(address(minimalAccount));
        // console.log(minimalAccount.owner());
        // console.log(address(randomUser));

        vm.prank(randomUser);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        // Act (continued)
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(minimalAccount));
    
        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

}