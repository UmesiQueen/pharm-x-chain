// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DrugRegistry} from "../../src/DrugRegistry.sol";
import {IGlobalRegistry, GlobalRegistry} from "../../src/GlobalRegistry.sol";

contract DrugRegistryTest is Test {
    GlobalRegistry public globalRegistry;
    DrugRegistry public drugRegistry;

    // =========================== ENTITY ADDRESSES ===========================
    address public REGULATOR = makeAddr("regulator");
    address public MANUFACTURER = makeAddr("manufacturer");
    address public SUPPLIER = makeAddr("supplier");
    address public PHARMACY = makeAddr("pharmacy");

    // =========================== MEDICINE DETAILS ===========================
    string public _name = "Paracetamol";
    string public _brand = "Exzol";
    string public _medicineId = "M-PAE01";
    string public _batchId = "B1-PAE01";
    uint256 public _quantity = 4000;
    uint256 public _productionDate = 1742888079;
    uint256 public _expiryDate = 1774424079;

    function setUp() public {
        vm.startPrank(REGULATOR);
        globalRegistry = new GlobalRegistry();

        // register entities
        globalRegistry.registerEntity(
            MANUFACTURER, IGlobalRegistry.Role.MANUFACTURER, "Russels", "flic en flac", "MFG201"
        );
        globalRegistry.registerEntity(SUPPLIER, IGlobalRegistry.Role.SUPPLIER, "De Bronx", "flic en flac", "SPL123");
        globalRegistry.registerEntity(
            PHARMACY, IGlobalRegistry.Role.PHARMACY, "Clinique du nord", "port louis", "PHA001"
        );
        drugRegistry = new DrugRegistry(address(globalRegistry));
        console2.log("DrugRegistry address: ", address(drugRegistry));
        console2.log("GlobalRegistry address: ", address(globalRegistry));
        console2.log("\n=========================================================================\n");
        vm.stopPrank();
    }

    modifier registerAndApproveMedicine() {
        vm.prank(MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _name, _brand);
        console2.log("Medicine registered with Id: ", _medicineId);

        // approve registered medicine
        vm.prank(REGULATOR);
        drugRegistry.approveMedicine(_medicineId);
        console2.log("Medicine with Id", _medicineId, "is approved!");
        console2.log("\n=========================================================================\n");
        _;
    }

    modifier createBatch() {
        vm.prank(MANUFACTURER);
        string memory newBatch =
            drugRegistry.createBatch(_medicineId, _batchId, _quantity, _productionDate, _expiryDate);

        console2.log("New batch created with ID: ", newBatch);
        console2.log("\n=========================================================================\n");
        _;
    }

    function testMedicineRegistration() public {
        vm.startPrank(MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _name, _brand);
        (
            string memory medicineId,
            string memory name,
            string memory brand,
            uint256 registrationDate,
            address manufacturer,
            ,
            bool approved
        ) = drugRegistry.getMedicineDetailsById(_medicineId);

        assertEq(medicineId, _medicineId);
        assertEq(name, _name);
        assertEq(brand, _brand);
        assertEq(registrationDate, block.timestamp);
        assertEq(manufacturer, MANUFACTURER);
        assertFalse(approved);
        vm.stopPrank();
    }

    function testRegulatorCanApproveMedicine() public {
        // register new medicine
        vm.prank(MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _name, _brand);

        // approve registered medicine
        vm.prank(REGULATOR);
        drugRegistry.approveMedicine(_medicineId);

        (string memory medicineId,,,,,, bool approved) = drugRegistry.getMedicineDetailsById(_medicineId);
        assertTrue(approved);

        console2.log("Medicine Id: ", medicineId);
        console2.log("Approved: ", approved);
    }

    function testManufacturerCanCreateNewMedicineBatch() public registerAndApproveMedicine {
        vm.prank(MANUFACTURER);
        string memory newBatch =
            drugRegistry.createBatch(_medicineId, _batchId, _quantity, _productionDate, _expiryDate);

        assertEq(newBatch, _batchId);
        console2.log("New batch created!\n  Batch ID: ", newBatch);
    }

    function testGetSupplyChainHistory() public registerAndApproveMedicine createBatch {
        // retrieve first supply chain event
        DrugRegistry.SupplyChainEvent memory chainEvents = (drugRegistry.getSupplyChainHistory(_medicineId))[0];
        DrugRegistry.EventType eventType = chainEvents.eventType;

        // convert eventType to string
        string memory eventTypeStr = convertEventTypeToString(eventType);

        assertEq("MANUFACTURED", eventTypeStr);

        // LOGS
        console2.log("MedicineID: ", chainEvents.medicineId);
        console2.log("BatchID: ", chainEvents.batchId);
        console2.log("EventType: ", eventTypeStr);
        console2.log("From: ", chainEvents.fromEntity);
        console2.log("To: ", chainEvents.toEntity);
        console2.log("Quantity: ", chainEvents.quantity);
        console2.log("Timestamp: ", chainEvents.timestamp);
        console2.log("PatientID: ", chainEvents.patientId);
    }

    // =========================== REVERTS ===========================

    function testRevertMedicineRegistrationWithMinLengthRequirement() public {
        string memory name = "P";

        vm.startPrank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DrugRegistry.DrugRegistry__MinLengthRequired.selector, "Medicine Name", bytes(name).length, 2
            )
        );
        drugRegistry.registerMedicine(_medicineId, name, _brand);
        vm.stopPrank();
    }

    function convertEventTypeToString(DrugRegistry.EventType eventType) public pure returns (string memory) {
        // convert eventType to string
        string memory eventTypeStr;
        if (eventType == DrugRegistry.EventType.MANUFACTURED) {
            eventTypeStr = "MANUFACTURED";
        } else if (eventType == DrugRegistry.EventType.TO_SUPPLIER) {
            eventTypeStr = "TO_SUPPLIER";
        } else if (eventType == DrugRegistry.EventType.TO_PHARMACY) {
            eventTypeStr = "TO_PHARMACY";
        } else if (eventType == DrugRegistry.EventType.DISPENSED) {
            eventTypeStr = "DISPENSED";
        }

        return eventTypeStr;
    }
}
