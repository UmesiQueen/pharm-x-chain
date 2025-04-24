// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DrugRegistry, IDrugRegistry} from "../../src/DrugRegistry.sol";
import {IGlobalRegistry, GlobalRegistry} from "../../src/GlobalRegistry.sol";
import {SupplyChainRegistry} from "../../src/SupplyChainRegistry.sol";

contract SupplyChainRegistryTest is Test {
    GlobalRegistry public globalRegistry;
    DrugRegistry public drugRegistry;
    SupplyChainRegistry public supplyChainRegistry;

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
    string public patientId = "P-1033";

    function setUp() public {
        vm.startPrank(REGULATOR);
        globalRegistry = new GlobalRegistry();
        drugRegistry = new DrugRegistry(address(globalRegistry));
        supplyChainRegistry = new SupplyChainRegistry(address(globalRegistry), address(drugRegistry));

        // register entities
        globalRegistry.registerEntity(
            MANUFACTURER, IGlobalRegistry.Role.MANUFACTURER, "Russels", "flic en flac", "MFG201", "L-1234"
        );
        globalRegistry.registerEntity(
            SUPPLIER, IGlobalRegistry.Role.SUPPLIER, "De Bronx", "flic en flac", "SPL123", "L-1234"
        );
        globalRegistry.registerEntity(
            PHARMACY, IGlobalRegistry.Role.PHARMACY, "Clinique du nord", "port louis", "PHA001", "L-1234"
        );

        //  Set the supply chain registry address on drugRegistryContract
        drugRegistry.setSupplyChainRegistry(address(supplyChainRegistry));

        console2.log("DrugRegistry address: ", address(drugRegistry));
        console2.log("GlobalRegistry address: ", address(globalRegistry));
        console2.log("SupplyChainRegistry address: ", address(supplyChainRegistry));
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
        drugRegistry.createBatch(_medicineId, _batchId, _quantity, _productionDate, _expiryDate);

        console2.log("New batch created with ID: ", _batchId);
        console2.log("\n=========================================================================\n");
        _;
    }

    //TODO:
    function test_InitializeBatchInventory() public {}

    function test_TransferOwnership() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to supplier
        vm.prank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, SUPPLIER, 200);

        // retrieve first supply chain event
        SupplyChainRegistry.SupplyChainEvent[] memory chainEvents =
            supplyChainRegistry.getSupplyChainHistory(_medicineId);

        SupplyChainRegistry.EventType eventType = chainEvents[1].eventType;
        // convert eventType to string
        string memory eventTypeStr = convertEventTypeToString(eventType);
        assertEq("TO_SUPPLIER", eventTypeStr);
    }

    function test_DispenseMedicine() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to pharmacy
        vm.prank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, 100);

        // dispense medicine to patient
        vm.prank(PHARMACY);
        supplyChainRegistry.dispenseMedicine(_batchId, 100, patientId);

        // retrieve first supply chain event
        SupplyChainRegistry.SupplyChainEvent[] memory chainEvents =
            supplyChainRegistry.getSupplyChainHistory(_medicineId);

        SupplyChainRegistry.EventType eventType = chainEvents[2].eventType;

        // convert eventType to string
        string memory eventTypeStr = convertEventTypeToString(eventType);
        assertEq("DISPENSED", eventTypeStr);

        console2.log(eventTypeStr, "eventType");
    }

    function test_VerifyAuthenticity() public view {
        bool isAuthentic = supplyChainRegistry.verifyAuthenticity("INVALID_ID");
        assertFalse(isAuthentic);
    }

    // =========================== REVERTS ===========================

    function test_RevertTransferOwnershipWithMinLengthRequirement() public registerAndApproveMedicine createBatch {
        uint256 quantity = 0;
        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyChainRegistry.SupplyChain__MinLengthRequired.selector, "Medicine Quantity", quantity, 1
            )
        );
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, quantity);
    }

    function test_RevertWithSenderIsNotAuthorizedToPerformAction() public registerAndApproveMedicine createBatch {
        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(SupplyChainRegistry.SupplyChain__SenderIsNotAuthorized.selector, MANUFACTURER)
        );
        supplyChainRegistry.dispenseMedicine(_batchId, 100, patientId);
    }

    function test_RevertWithBatchDoesNotExist() public registerAndApproveMedicine {
        // attempt to transfer a batch that does not exist
        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__BatchExistenceStatus.selector, _batchId, false)
        );
        supplyChainRegistry.transferOwnership(_batchId, SUPPLIER, 200);
    }

    function test_RevertWithBatchIsNotActive() public registerAndApproveMedicine createBatch {
        vm.startPrank(MANUFACTURER);
        // deactivate batch
        drugRegistry.deactivateBatch(_batchId, _medicineId);

        vm.expectRevert(abi.encodeWithSelector(SupplyChainRegistry.SupplyChain__BatchIsNotActive.selector, _batchId));
        supplyChainRegistry.transferOwnership(_batchId, SUPPLIER, 200);
        vm.stopPrank();
    }

    function test_RevertWithSenderHasInsufficientQuantity() public registerAndApproveMedicine createBatch {
        // get remaining quantity from manufacturer's inventory
        uint256 remainingQuantity = supplyChainRegistry.getInventory(MANUFACTURER, _medicineId);
        uint256 requestedQuantity = remainingQuantity + 1;

        // transfer from manufacturer to pharmacy
        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyChainRegistry.SupplyChain__SenderHasInsufficientQuantity.selector,
                requestedQuantity,
                remainingQuantity
            )
        );
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, requestedQuantity);
    }

    function test_RevertWithReceiverIsNotEligible() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to pharmacy
        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(SupplyChainRegistry.SupplyChain__ReceiverIsNotEligible.selector, REGULATOR)
        );
        supplyChainRegistry.transferOwnership(_batchId, REGULATOR, 100);
        console2.log("Receiver cannot be regulator!");
    }

    // =========================== GETTER FUNCTIONS ===========================
    function test_GetInventory() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to pharmacy
        vm.prank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, 100);

        uint256 inventory = supplyChainRegistry.getInventory(MANUFACTURER, _medicineId);

        assertLe(inventory, _quantity);

        console2.log("Manufacturer", MANUFACTURER);
        console2.log("MedicineID: ", _medicineId);
        console2.log("Inventory Quantity: ", inventory);
    }

    function test_BatchRemainingQuantityOnlyDecreasesWithManufacturerTransfer()
        public
        registerAndApproveMedicine
        createBatch
    {
        // transfer from manufacturer to supplier
        vm.prank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, SUPPLIER, 200);

        // transfer from supplier to pharmacy
        vm.prank(SUPPLIER);
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, 100);

        DrugRegistry.Batch memory batch = drugRegistry.getBatchDetails(_batchId);

        uint256 expectedRemainingQuantity = (_quantity - 200);
        assertEq(batch.remainingQuantity, expectedRemainingQuantity);
    }

    function test_GetAllMedicineHolderDetails() public registerAndApproveMedicine createBatch {
        // Register another pharmacy
        address PHARMACY2 = makeAddr("pharmacy2");

        vm.prank(REGULATOR);
        globalRegistry.registerEntity(
            PHARMACY2, IGlobalRegistry.Role.PHARMACY, "Rose Hill Clinic", "port louis", "PHA001", "L-1234"
        );

        // transfer from manufacturer to pharmacy
        vm.startPrank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, 100);
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY2, 350);
        vm.stopPrank();

        // get pharmacy availability
        SupplyChainRegistry.MedicineHoldersStock[] memory medicineHolderStock =
            supplyChainRegistry.getMedicineHoldersDetails(_medicineId);

        // check if the pharmacy stock is correct
        for (uint256 i = 0; i < medicineHolderStock.length; i++) {
            if (medicineHolderStock[i].holderAddress == PHARMACY) {
                assertEq(medicineHolderStock[i].availableQuantity, 100);
            } else if (medicineHolderStock[i].holderAddress == PHARMACY2) {
                assertEq(medicineHolderStock[i].availableQuantity, 350);
            }
        }
        console2.log("Medicine holders for medicine ID: ", _medicineId);
        console2.log("Number of holders with drug: ", medicineHolderStock.length);

        // log pharmacy stock
        for (uint256 i = 0; i < medicineHolderStock.length; i++) {
            console2.log("\n=========================================================================\n");
            console2.log("Medicine Holders ", i + 1);
            console2.log("Address: ", medicineHolderStock[i].holderAddress);
            console2.log("Name: ", medicineHolderStock[i].holderName);
            console2.log("Location: ", medicineHolderStock[i].holderLocation);
            console2.log("BatchId: ", medicineHolderStock[i].batchId);
            console2.log("Available Quantity: ", medicineHolderStock[i].availableQuantity);
        }
    }

    function test_GetMedicineHolders() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to pharmacy
        vm.prank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, 100);

        SupplyChainRegistry.MedicineHolder[] memory medicineHolders =
            supplyChainRegistry.getMedicineHolders(_medicineId);

        assertEq(medicineHolders.length, 2);

        for (uint256 i = 0; i < medicineHolders.length; i++) {
            console2.log("Batch ID: ", medicineHolders[i].holderAddress);
            console2.log("Batch ID: ", medicineHolders[i].batchId);
        }
    }

    function test_GetSupplyChainHistory() public registerAndApproveMedicine createBatch {
        // retrieve first supply chain event
        SupplyChainRegistry.SupplyChainEvent memory firstChainEvent =
            (supplyChainRegistry.getSupplyChainHistory(_medicineId))[0];
        SupplyChainRegistry.EventType eventType = firstChainEvent.eventType;

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

    function test_GetBatchEvents() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to pharmacy
        vm.startPrank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, 100);

        SupplyChainRegistry.SupplyChainEvent[] memory batchEvents = supplyChainRegistry.getBatchEvents(_batchId);

        assertEq(batchEvents.length, 2);
    }

    // =========================== EVENTS ===========================
    function test_EmitsMedicineTransferred() public registerAndApproveMedicine createBatch {
        vm.prank(MANUFACTURER);
        vm.expectEmit(true, true, true, true);
        emit SupplyChainRegistry.MedicineTransferred(_batchId, MANUFACTURER, SUPPLIER, 200);
        supplyChainRegistry.transferOwnership(_batchId, SUPPLIER, 200);
    }

    function test_EmitsMedicineDispensed() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to pharmacy
        vm.prank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, 100);

        vm.prank(PHARMACY);
        vm.expectEmit(false, false, false, false);
        emit SupplyChainRegistry.MedicineDispensed(_batchId, PHARMACY, "P-1033", 1);
        supplyChainRegistry.dispenseMedicine(_batchId, 100, "P-1033");
    }

    function test_EmitsLowInventoryAlert() public registerAndApproveMedicine createBatch {
        // transfer from manufacturer to pharmacy
        vm.prank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, 100);

        vm.prank(PHARMACY);
        vm.expectEmit(true, true, true, true);
        emit SupplyChainRegistry.LowInventoryAlert(PHARMACY, _batchId, 10);
        emit SupplyChainRegistry.MedicineDispensed(_batchId, PHARMACY, patientId, 90);
        supplyChainRegistry.dispenseMedicine(_batchId, 90, patientId);

        uint256 remainingQty = supplyChainRegistry.getInventory(PHARMACY, _medicineId);
        assert(remainingQty == 10);
        console2.log("Remaining Quantity: ", remainingQty);
    }

    // =========================== HELPER FUNCTION ===========================
    function convertEventTypeToString(SupplyChainRegistry.EventType eventType) internal pure returns (string memory) {
        // convert eventType to string
        string memory eventTypeStr;
        if (eventType == SupplyChainRegistry.EventType.MANUFACTURED) {
            eventTypeStr = "MANUFACTURED";
        } else if (eventType == SupplyChainRegistry.EventType.TO_SUPPLIER) {
            eventTypeStr = "TO_SUPPLIER";
        } else if (eventType == SupplyChainRegistry.EventType.TO_PHARMACY) {
            eventTypeStr = "TO_PHARMACY";
        } else if (eventType == SupplyChainRegistry.EventType.DISPENSED) {
            eventTypeStr = "DISPENSED";
        }

        return eventTypeStr;
    }
}
