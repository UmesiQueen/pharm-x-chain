// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {GlobalRegistry, IGlobalRegistry} from "../../src/GlobalRegistry.sol";
import {DeployGlobalRegistryScript} from "../../script/DeployGlobalRegistry.s.sol";

contract GlobalRegistryTest is Test {
    GlobalRegistry public globalRegistry;

    address public REGULATOR; // owner
    address public MANUFACTURER = makeAddr("manufacturer");

    function setUp() public {
        // Deploy contract and set owner
        REGULATOR = makeAddr("regulator");

        vm.startPrank(REGULATOR);
        globalRegistry = new GlobalRegistry();
        vm.stopPrank();
    }

    modifier registerEntity() {
        vm.prank(REGULATOR);
        globalRegistry.registerEntity(
            MANUFACTURER, IGlobalRegistry.Role.MANUFACTURER, "Manufacturer1", "flic-en-flac", "MFR123"
        );
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
        vm.prank(MANUFACTURER);

        vm.expectRevert(GlobalRegistry.GlobalRegistry__SenderIsNotOwner.selector);
        globalRegistry.registerEntity(
            MANUFACTURER, IGlobalRegistry.Role.MANUFACTURER, "Manufacturer1", "flic-en-flac", "MFR123"
        );
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
        globalRegistry.deactivateEntity(MANUFACTURER);

        (,,,, bool isActive,) = (globalRegistry.getEntityDetails(MANUFACTURER));

        vm.expectRevert(
            abi.encodeWithSelector(
                GlobalRegistry.GlobalRegistry__EntityAlreadyDeactivated.selector, MANUFACTURER, isActive
            )
        );
        globalRegistry.deactivateEntity(MANUFACTURER);

        vm.stopPrank();
    }

    function testRevertEntityAlreadyActivated() public registerEntity {
        vm.startPrank(REGULATOR);
        vm.expectRevert(
            abi.encodeWithSelector(GlobalRegistry.GlobalRegistry__EntityAlreadyActivated.selector, MANUFACTURER, true)
        );
        globalRegistry.activateEntity(MANUFACTURER);
        vm.stopPrank();
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
        globalRegistry.registerEntity(
            MANUFACTURER, IGlobalRegistry.Role.MANUFACTURER, "Manufacturer1", "flic-en-flac", "MFR123"
        );
    }

    // ================ EVENT TESTS ================
    function testEntityRegistrationEmitsEvent() public {
        vm.prank(REGULATOR);

        vm.expectEmit(true, false, false, false);
        emit GlobalRegistry.EntityRegistered(MANUFACTURER, IGlobalRegistry.Role.MANUFACTURER, "Manufacturer1");

        globalRegistry.registerEntity(
            MANUFACTURER, IGlobalRegistry.Role.MANUFACTURER, "Manufacturer1", "flic-en-flac", "MFR123"
        );
    }

    function testEntityDeactivationEmitsEvent() public registerEntity {
        vm.prank(REGULATOR);
        vm.expectEmit(true, false, false, false);
        emit GlobalRegistry.EntityDeactivated(MANUFACTURER);

        globalRegistry.deactivateEntity(MANUFACTURER);
    }

    function testEntityActivationEmitsEvent() public registerEntity {
        vm.startPrank(REGULATOR);
        globalRegistry.deactivateEntity(MANUFACTURER);

        vm.expectEmit(true, false, false, false);
        emit GlobalRegistry.EntityActivated(MANUFACTURER);
        globalRegistry.activateEntity(MANUFACTURER);
        vm.stopPrank();
    }
}
