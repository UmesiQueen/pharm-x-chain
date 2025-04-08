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
    uint256 public _productionDate = block.timestamp;
    uint256 public interval = 63113852; // 2 years
    uint256 public _expiryDate = _productionDate + interval;

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
        vm.prank(MANUFACTURER);
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

    function testTransferOwnership() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to supplier
        vm.prank(MANUFACTURER);
        drugRegistry.transferOwnership(_batchId, SUPPLIER, 200);

        // retrieve first supply chain event
        DrugRegistry.SupplyChainEvent[] memory chainEvents = drugRegistry.getSupplyChainHistory(_medicineId);

        DrugRegistry.EventType eventType = chainEvents[1].eventType;
        // convert eventType to string
        string memory eventTypeStr = convertEventTypeToString(eventType);
        assertEq("TO_SUPPLIER", eventTypeStr);
    }

    function testDispenseMedicine() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to pharmacy
        vm.prank(MANUFACTURER);
        drugRegistry.transferOwnership(_batchId, PHARMACY, 100);

        // dispense medicine to patient
        vm.prank(PHARMACY);
        drugRegistry.dispenseMedicine(_batchId, 100, "P-1033");

        // retrieve first supply chain event
        DrugRegistry.SupplyChainEvent[] memory chainEvents = drugRegistry.getSupplyChainHistory(_medicineId);

        DrugRegistry.EventType eventType = chainEvents[2].eventType;

        // convert eventType to string
        string memory eventTypeStr = convertEventTypeToString(eventType);
        assertEq("DISPENSED", eventTypeStr);

        console2.log(eventTypeStr, "eventType");
    }

    function testVerifyAuthenticity() public view {
        bool isAuthentic = drugRegistry.verifyAuthenticity("INVALID_ID");
        assertFalse(isAuthentic);
    }

    function testDeactivateExpiredBatch() public registerAndApproveMedicine createBatch {
        // set timestamp to 2 years in the future
        vm.warp(block.timestamp + interval + 1);
        //  Set block.number
        vm.roll(block.number + 1);

        vm.expectEmit(true, false, false, true);
        emit DrugRegistry.BatchDeactivated(_batchId, "Expired");
        drugRegistry.deactivateExpiredBatch(_batchId);

        // check if batch is deactivated
        DrugRegistry.Batch memory batch = drugRegistry.getBatchDetails(_batchId);
        assertFalse(batch.isActive);
        console2.log("Batch status: ", batch.isActive);
        console2.log("Current block.timestamp: ", block.timestamp);
        console2.log("Batch expiry date: ", batch.expiryDate);
    }

    // =========================== REVERTS ===========================

    function testRevertMedicineRegistrationWithMinLengthRequirement() public {
        string memory name = "P";

        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DrugRegistry.DrugRegistry__MinLengthRequired.selector, "Medicine Name", bytes(name).length, 2
            )
        );
        drugRegistry.registerMedicine(_medicineId, name, _brand);
    }

    function testRevertWithSenderIsNotAuthorizedToPerformAction() public {
        vm.startPrank(MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _name, _brand);

        vm.expectRevert(abi.encodeWithSelector(DrugRegistry.DrugRegistry__SenderIsNotAuthorized.selector, MANUFACTURER));
        drugRegistry.approveMedicine(_medicineId);
        vm.stopPrank();
    }

    function testRevertWithMedicineDoesNotExist() public {
        // attempt to approve a medicine that hasn't been registered
        vm.prank(REGULATOR);
        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__MedicineExistenceStatus.selector, _medicineId, false)
        );
        drugRegistry.approveMedicine(_medicineId);
    }

    function testRevertWithMedicineAlreadyExists() public registerAndApproveMedicine {
        // attempt to register a medicine that has already been registered
        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__MedicineExistenceStatus.selector, _medicineId, true)
        );
        drugRegistry.registerMedicine(_medicineId, _name, _brand);
    }

    function testRevertWithBatchAlreadyExists() public registerAndApproveMedicine createBatch {
        // attempt to create a batch with the same batchId
        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__BatchExistenceStatus.selector, _batchId, true)
        );
        drugRegistry.createBatch(_medicineId, _batchId, _quantity, _productionDate, _expiryDate);
        console2.log("Batch already exists!");
    }

    function testRevertWithBatchDoesNotExist() public registerAndApproveMedicine {
        // attempt to transfer a batch that does not exist
        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__BatchExistenceStatus.selector, _batchId, false)
        );
        drugRegistry.transferOwnership(_batchId, SUPPLIER, 200);
    }

    function testRevertWithBatchIsNotActive() public registerAndApproveMedicine createBatch {
        // set timestamp to 2 years in the future
        vm.warp(block.timestamp + interval + 1);
        //  Set block.number
        vm.roll(block.number + 1);

        // deactivate batch
        drugRegistry.deactivateExpiredBatch(_batchId);

        vm.prank(MANUFACTURER);
        vm.expectRevert(abi.encodeWithSelector(DrugRegistry.DrugRegistry__BatchIsNotActive.selector, _batchId));
        drugRegistry.transferOwnership(_batchId, SUPPLIER, 200);
    }

    function testRevertWithMedicineIsAlreadyApproved() public registerAndApproveMedicine {
        vm.prank(REGULATOR);
        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__MedicineApprovalStatus.selector, _medicineId, true)
        );
        drugRegistry.approveMedicine(_medicineId);
    }

    function testRevertWithMedicineNotApproved() public {
        vm.startPrank(MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _name, _brand);

        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__MedicineApprovalStatus.selector, _medicineId, false)
        );
        drugRegistry.createBatch(_medicineId, _batchId, _quantity, _productionDate, _expiryDate);
        vm.stopPrank();
    }

    function testRevertWithSenderHasInsufficientQuantity() public registerAndApproveMedicine createBatch {
        // get remaining quantity from manufacturer's inventory
        uint256 remainingQuantity = drugRegistry.getInventory(MANUFACTURER, _medicineId);
        uint256 requestedQuantity = remainingQuantity + 1;

        // transfer from manufacturer to pharmacy
        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DrugRegistry.DrugRegistry__SenderHasInsufficientQuantity.selector, requestedQuantity, remainingQuantity
            )
        );
        drugRegistry.transferOwnership(_batchId, PHARMACY, requestedQuantity);
    }

    function testRevertWithReceiverIsNotEligible() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to pharmacy
        vm.prank(MANUFACTURER);
        vm.expectRevert(abi.encodeWithSelector(DrugRegistry.DrugRegistry__ReceiverIsNotEligible.selector, REGULATOR));
        drugRegistry.transferOwnership(_batchId, REGULATOR, 100);
        console2.log("Receiver cannot be regulator!");
    }

    // =========================== GETTER FUNCTIONS ===========================
    function testGetMedicineDetailsById() public registerAndApproveMedicine {
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
        assertTrue(approved);
    }

    function testGetBatchDetails() public registerAndApproveMedicine createBatch {
        DrugRegistry.Batch memory batch = drugRegistry.getBatchDetails(_batchId);

        assertEq(batch.batchId, _batchId);
        assertEq(batch.medicineId, _medicineId);

        console2.log("BatchID: ", batch.batchId);
        console2.log("MedicineID: ", batch.medicineId);
        console2.log("Quantity: ", batch.quantity);
        console2.log("RemainingQuantity: ", batch.remainingQuantity);
        console2.log("ProductionDate: ", batch.productionDate);
        console2.log("ExpiryDate: ", batch.expiryDate);
        console2.log("isActive: ", batch.isActive);
    }

    function testGetInventory() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to pharmacy
        vm.prank(MANUFACTURER);
        drugRegistry.transferOwnership(_batchId, PHARMACY, 100);

        uint256 inventory = drugRegistry.getInventory(MANUFACTURER, _medicineId);

        assertLe(inventory, _quantity);

        console2.log("Manufacturer", MANUFACTURER);
        console2.log("MedicineID: ", _medicineId);
        console2.log("Inventory Quantity: ", inventory);
    }

    function testBatchRemainingQuantityOnlyDecreasesWithManufacturerTransfer()
        public
        registerAndApproveMedicine
        createBatch
    {
        // transfer from manufacturer to supplier
        vm.prank(MANUFACTURER);
        drugRegistry.transferOwnership(_batchId, SUPPLIER, 200);

        // transfer from supplier to pharmacy
        vm.prank(SUPPLIER);
        drugRegistry.transferOwnership(_batchId, PHARMACY, 100);

        DrugRegistry.Batch memory batch = drugRegistry.getBatchDetails(_batchId);

        uint256 expectedRemainingQuantity = (_quantity - 200);
        assertEq(batch.remainingQuantity, expectedRemainingQuantity);
    }

    function testGetPharmacyAvailability() public registerAndApproveMedicine createBatch {
        // Register another pharmacy
        address PHARMACY2 = makeAddr("pharmacy2");

        vm.prank(REGULATOR);
        globalRegistry.registerEntity(
            PHARMACY2, IGlobalRegistry.Role.PHARMACY, "Rose Hill Clinic", "port louis", "PHA001"
        );

        // transfer from manufacturer to pharmacy
        vm.startPrank(MANUFACTURER);
        drugRegistry.transferOwnership(_batchId, PHARMACY, 100);
        drugRegistry.transferOwnership(_batchId, PHARMACY2, 350);
        vm.stopPrank();

        // get pharmacy availability
        DrugRegistry.PharmacyStock[] memory pharmacyStock = drugRegistry.getPharmacyAvailability(_medicineId);

        // check if the pharmacy stock is correct
        for (uint256 i = 0; i < pharmacyStock.length; i++) {
            if (pharmacyStock[i].pharmacyAddress == PHARMACY) {
                assertEq(pharmacyStock[i].availableQuantity, 100);
            } else if (pharmacyStock[i].pharmacyAddress == PHARMACY2) {
                assertEq(pharmacyStock[i].availableQuantity, 350);
            }
        }
        console2.log("Pharmacy availability for medicine ID: ", _medicineId);
        console2.log("Number of Pharmacies with drug: ", pharmacyStock.length);

        // log pharmacy stock
        for (uint256 i = 0; i < pharmacyStock.length; i++) {
            console2.log("\n=========================================================================\n");
            console2.log("Pharmacy ", i + 1);
            console2.log("Address: ", pharmacyStock[i].pharmacyAddress);
            console2.log("Name: ", pharmacyStock[i].pharmacyName);
            console2.log("Location: ", pharmacyStock[i].location);
            console2.log("Available Quantity: ", pharmacyStock[i].availableQuantity);
        }
    }

    function testGetSupplyChainHistory() public registerAndApproveMedicine createBatch {
        // retrieve first supply chain event
        DrugRegistry.SupplyChainEvent memory firstChainEvent = (drugRegistry.getSupplyChainHistory(_medicineId))[0];
        DrugRegistry.EventType eventType = firstChainEvent.eventType;

        // convert eventType to string
        string memory eventTypeStr = convertEventTypeToString(eventType);

        assertEq("MANUFACTURED", eventTypeStr);

        // LOGS
        console2.log("MedicineID: ", firstChainEvent.medicineId);
        console2.log("BatchID: ", firstChainEvent.batchId);
        console2.log("EventType: ", eventTypeStr);
        console2.log("From: ", firstChainEvent.fromEntity);
        console2.log("To: ", firstChainEvent.toEntity);
        console2.log("Quantity: ", firstChainEvent.quantity);
        console2.log("Timestamp: ", firstChainEvent.timestamp);
        console2.log("PatientID: ", firstChainEvent.patientId);
    }

    function testGetMedicineBatches() public registerAndApproveMedicine createBatch {
        // Create 2nd batch
        vm.prank(MANUFACTURER);
        drugRegistry.createBatch(_medicineId, "B1-PAE02", _quantity, _productionDate, _expiryDate);

        string[] memory batchIds = drugRegistry.getMedicineBatches(_medicineId);

        assertEq(batchIds.length, 2);
        for (uint256 i = 0; i < batchIds.length; i++) {
            console2.log("Batch ID: ", batchIds[i]);
        }
    }

    function testGetBatchEvents() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to pharmacy
        vm.startPrank(MANUFACTURER);
        drugRegistry.transferOwnership(_batchId, PHARMACY, 100);

        DrugRegistry.SupplyChainEvent[] memory batchEvents = drugRegistry.getBatchEvents(_batchId);

        assertEq(batchEvents.length, 2);
    }

    // =========================== EVENTS ===========================
    function testEmitsMedicineRegisteredEvent() public {
        vm.prank(MANUFACTURER);
        vm.expectEmit(true, false, false, true);
        emit DrugRegistry.MedicineRegistered(_medicineId, _name, MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _name, _brand);
    }

    function testEmitsMedicineApprovedEvent() public {
        vm.prank(MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _name, _brand);

        vm.prank(REGULATOR);
        vm.expectEmit(true, false, false, true);
        emit DrugRegistry.MedicineApproved(_medicineId, MANUFACTURER);
        drugRegistry.approveMedicine(_medicineId);
    }

    function testEmitsBatchCreatedEvent() public registerAndApproveMedicine {
        vm.prank(MANUFACTURER);
        vm.expectEmit(true, false, false, true);
        emit DrugRegistry.BatchCreated(_batchId, _medicineId, _quantity);
        drugRegistry.createBatch(_medicineId, _batchId, _quantity, _productionDate, _expiryDate);
    }

    function testEmitsMedicineTransferred() public registerAndApproveMedicine createBatch {
        vm.prank(MANUFACTURER);
        vm.expectEmit(true, true, true, true);
        emit DrugRegistry.MedicineTransferred(_batchId, MANUFACTURER, SUPPLIER, 200);
        drugRegistry.transferOwnership(_batchId, SUPPLIER, 200);
    }

    function testEmitsMedicineDispensed() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to pharmacy
        vm.prank(MANUFACTURER);
        drugRegistry.transferOwnership(_batchId, PHARMACY, 100);

        vm.prank(PHARMACY);
        vm.expectEmit(false, false, false, false);
        emit DrugRegistry.MedicineDispensed(_batchId, PHARMACY, "P-1033", 1);
        drugRegistry.dispenseMedicine(_batchId, 100, "P-1033");
    }

    // =========================== HELPER FUNCTION ===========================
    function convertEventTypeToString(DrugRegistry.EventType eventType) internal pure returns (string memory) {
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
