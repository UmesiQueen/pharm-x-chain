// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {GlobalRegistry, IGlobalRegistry} from "../../src/GlobalRegistry.sol";
import {DeployGlobalRegistryScript} from "../../script/DeployGlobalRegistry.s.sol";

contract GlobalRegistryTest is Test {
    GlobalRegistry public globalRegistry;

    address public REGULATOR; // owner
    address public MANUFACTURER = makeAddr("manufacturer");
    address public SUPPLIER = makeAddr("supplier");
    address public PHARMACY = makeAddr("pharmacy");

    function setUp() public {
        // Deploy contract and set owner
        vm.startPrank(address(this));
        globalRegistry = new GlobalRegistry();
        REGULATOR = address(this);
        vm.stopPrank();
    }

    modifier registerEntity() {
        vm.prank(REGULATOR);
        globalRegistry.registerManufacturer(MANUFACTURER, "Manufacturer1", "flic-en-flac", "MFR123");
        globalRegistry.registerSupplier(SUPPLIER, "Supplier1", "flic-en-flac", "SUP123");
        globalRegistry.registerPharmacy(PHARMACY, "Pharmacy1", "flic-en-flac", "PHM123");
        _;
    }

    // ================ DEPLOYMENT TESTS ================
    function testDeployment() public view {
        // Check owner
        assertEq(globalRegistry.owner(), REGULATOR);

        // Check deployer details
        (,,, IGlobalRegistry.Role role,,) = globalRegistry.getEntityDetails(REGULATOR);
        assertEq(uint256(role), uint256(IGlobalRegistry.Role.REGULATOR));
    }

    // ================ REGISTRATION TESTS ================
    function testOnlyOwnerCanRegister() public {
        vm.prank(SUPPLIER);

        vm.expectRevert(GlobalRegistry.GlobalRegistry__SenderIsNotOwner.selector);
        globalRegistry.registerManufacturer(MANUFACTURER, "Manufacturer1", "flic-en-flac", "MFR123");
    }

    function testRegisterManufacturer() public {
        vm.prank(REGULATOR);
        globalRegistry.registerManufacturer(MANUFACTURER, "Manufacturer1", "flic-en-flac", "MFR123");
        assertTrue(globalRegistry.verifyEntity(MANUFACTURER));
    }

    function testEntityVerification() public registerEntity {
        assertTrue(globalRegistry.verifyEntity(MANUFACTURER));
    }

    function testGetEntityRole() public registerEntity {
        IGlobalRegistry.Role role = globalRegistry.getEntityRole(MANUFACTURER);
        assertEq(uint256(role), uint256(IGlobalRegistry.Role.MANUFACTURER));
    }

    // ================ REVERT TESTS ================
    function testRevertWithEntityDoesNotExist() public {
        vm.prank(REGULATOR);
        vm.expectRevert(GlobalRegistry.GlobalRegistry__EntityDoesNotExist.selector);
        globalRegistry.deactivateEntity(MANUFACTURER);
    }

    function testRevertWithEntityAlreadyDeactivated() public registerEntity {
        vm.startPrank(REGULATOR);
        globalRegistry.deactivateEntity(SUPPLIER);

        (,,,, bool isActive,) = globalRegistry.getEntityDetails(SUPPLIER);

        vm.expectRevert(
            abi.encodeWithSelector(GlobalRegistry.GlobalRegistry__EntityAlreadyDeactivated.selector, SUPPLIER, isActive)
        );
        globalRegistry.deactivateEntity(SUPPLIER);

        vm.stopPrank();
    }

    function testRevertEntityAlreadyActivated() public registerEntity {
        vm.expectRevert(
            abi.encodeWithSelector(GlobalRegistry.GlobalRegistry__EntityAlreadyActivated.selector, SUPPLIER, true)
        );
        globalRegistry.activateEntity(SUPPLIER);
    }

    function testRevertWithEntityAlreadyRegistered() public registerEntity {
        vm.prank(REGULATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                GlobalRegistry.GlobalRegistry__EntityAlreadyRegistered.selector,
                MANUFACTURER,
                IGlobalRegistry.Role.MANUFACTURER
            )
        );
        globalRegistry.registerManufacturer(MANUFACTURER, "Manufacturer1", "flic-en-flac", "MFR123");
    }

    // ================ EVENT TESTS ================
    function testEntityRegistrationEmitsEvent() public {
        vm.prank(REGULATOR);

        vm.expectEmit(true, false, false, false);
        emit GlobalRegistry.EntityRegistered(MANUFACTURER, IGlobalRegistry.Role.MANUFACTURER, "Manufacturer1");

        globalRegistry.registerManufacturer(MANUFACTURER, "Manufacturer1", "flic-en-flac", "MFR123");
    }

    function testEntityDeactivationEmitsEvent() public registerEntity {
        vm.prank(REGULATOR);
        vm.expectEmit(true, false, false, false);
        emit GlobalRegistry.EntityDeactivated(PHARMACY);

        globalRegistry.deactivateEntity(PHARMACY);
    }

    function testEntityActivationEmitsEvent() public registerEntity {
        vm.prank(REGULATOR);
        globalRegistry.deactivateEntity(PHARMACY);

        vm.expectEmit(true, false, false, false);
        emit GlobalRegistry.EntityActivated(PHARMACY);

        globalRegistry.activateEntity(PHARMACY);
    }
}
