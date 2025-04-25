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
    string public _serialNo = "563-58d9-7e13";
    string public _ingredients = "Ascorbic Acid 250mg, calcium stearate 30g ";
    string public _details = "Maybe cause drowsiness";
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
        drugRegistry.registerMedicine(_medicineId, _serialNo, _name, _brand, _ingredients, _details);
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

    function test_InitializeBatchInventory() public registerAndApproveMedicine {
        // First check that the manufacturer has no available quantity before batch initialization
        uint256 manufacturerInventory = supplyChainRegistry.getInventory(MANUFACTURER, _medicineId);
        assertEq(manufacturerInventory, 0);

        // Create batch
        vm.prank(MANUFACTURER);
        drugRegistry.createBatch(_medicineId, _batchId, _quantity, _productionDate, _expiryDate);

        // Check that manufacturer inventory is updated
        manufacturerInventory = supplyChainRegistry.getInventory(MANUFACTURER, _medicineId);
        assertEq(manufacturerInventory, _quantity);

        // Check that MANUFACTURER has this medicineId in its list
        string[] memory manufacturerMedicineIds = supplyChainRegistry.getAddressMedicineIds(MANUFACTURER);
        bool found = false;
        for (uint256 i = 0; i < manufacturerMedicineIds.length; i++) {
            if (keccak256(bytes(manufacturerMedicineIds[i])) == keccak256(bytes(_medicineId))) {
                found = true;
                break;
            }
        }
        assertTrue(found);

        // Verify supply chain event was recorded accurately
        SupplyChainRegistry.SupplyChainEvent[] memory events = supplyChainRegistry.getSupplyChainHistory(_medicineId);
        assertEq(events.length, 1, "Should be one supply chain event after batch creation");
        assertEq(events[0].quantity, _quantity, "Event quantity should match batch quantity");
        assertEq(events[0].toEntity, MANUFACTURER, "Event recipient should be manufacturer");
    }

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

    function test_ComplexSupplyChainFlow() public registerAndApproveMedicine createBatch {
        // MANUFACTURER -> SUPPLIER (2000)
        vm.prank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, SUPPLIER, 2000);

        // MANUFACTURER -> PHARMACY (1000)
        vm.prank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, 1000);

        // Check inventories after initial transfers
        assertEq(supplyChainRegistry.getInventory(MANUFACTURER, _medicineId), 1000);
        assertEq(supplyChainRegistry.getInventory(SUPPLIER, _medicineId), 2000);
        assertEq(supplyChainRegistry.getInventory(PHARMACY, _medicineId), 1000);

        // SUPPLIER -> PHARMACY (500)
        vm.prank(SUPPLIER);
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, 500);

        // Check inventories after supplier transfer
        assertEq(supplyChainRegistry.getInventory(SUPPLIER, _medicineId), 1500);
        assertEq(supplyChainRegistry.getInventory(PHARMACY, _medicineId), 1500);

        // PHARMACY dispenses medicine (800)
        vm.prank(PHARMACY);
        supplyChainRegistry.dispenseMedicine(_batchId, 800, patientId);

        // Check pharmacy inventory after dispensing
        assertEq(supplyChainRegistry.getInventory(PHARMACY, _medicineId), 700);

        // PHARMACY dispenses all remaining medicine (700)
        vm.prank(PHARMACY);
        supplyChainRegistry.dispenseMedicine(_batchId, 700, patientId);

        // Check pharmacy inventory is zero and medicineId is removed from its list
        assertEq(supplyChainRegistry.getInventory(PHARMACY, _medicineId), 0);

        string[] memory pharmacyMedicineIds = supplyChainRegistry.getAddressMedicineIds(PHARMACY);
        bool found = false;
        for (uint256 i = 0; i < pharmacyMedicineIds.length; i++) {
            if (keccak256(bytes(pharmacyMedicineIds[i])) == keccak256(bytes(_medicineId))) {
                found = true;
                break;
            }
        }
        assertFalse(found, "MedicineId should be removed from pharmacy's list after dispensing all inventory");

        // Check that supplier and manufacturer still have their medicine
        assertTrue(supplyChainRegistry.getInventory(SUPPLIER, _medicineId) > 0);
        assertTrue(supplyChainRegistry.getInventory(MANUFACTURER, _medicineId) > 0);
    }

    function test_VerifyAuthenticity() public view {
        bool isAuthentic = supplyChainRegistry.verifyAuthenticity("INVALID_ID");
        assertFalse(isAuthentic);
    }

    function test_AddressMedicineIdsAddedOnBatchInitialization() public registerAndApproveMedicine createBatch {
        // After batch initialization, manufacturer should have the medicineId in their list
        string[] memory manufacturerMedicineIds = supplyChainRegistry.getAddressMedicineIds(MANUFACTURER);

        // Check that the list exists and has the correct medicineId
        assertEq(manufacturerMedicineIds.length, 1);
        assertEq(manufacturerMedicineIds[0], _medicineId);

        console2.log("Manufacturer has medicineId after batch initialization: ", manufacturerMedicineIds[0]);
    }

    function test_AddressMedicineIdsAddedOnTransfer() public registerAndApproveMedicine createBatch {
        // Transfer medicine to supplier
        vm.prank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, SUPPLIER, 200);

        // Check supplier's medicineIds list
        string[] memory supplierMedicineIds = supplyChainRegistry.getAddressMedicineIds(SUPPLIER);

        // Verify supplier now has the medicineId
        assertEq(supplierMedicineIds.length, 1);
        assertEq(supplierMedicineIds[0], _medicineId);

        console2.log("Supplier has medicineId after transfer: ", supplierMedicineIds[0]);
    }

    function test_NoDuplicateMedicineIds() public registerAndApproveMedicine createBatch {
        // Register another batch of the same medicine
        string memory secondBatchId = "B2-PAE01";

        vm.prank(MANUFACTURER);
        drugRegistry.createBatch(_medicineId, secondBatchId, _quantity, _productionDate, _expiryDate);

        // Now manufacturer should still only have one entry for this medicineId
        string[] memory manufacturerMedicineIds = supplyChainRegistry.getAddressMedicineIds(MANUFACTURER);

        assertEq(manufacturerMedicineIds.length, 1, "Should not have duplicate medicineIds");
        assertEq(manufacturerMedicineIds[0], _medicineId);

        console2.log(
            "Manufacturer has correct number of medicineIds after multiple batches: ", manufacturerMedicineIds.length
        );
    }

    function test_MultipleMedicineIdsPerAddress() public {
        // Register first medicine and batch
        vm.startPrank(MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _serialNo, _name, _brand, _ingredients, _details);
        vm.stopPrank();

        vm.prank(REGULATOR);
        drugRegistry.approveMedicine(_medicineId);

        vm.prank(MANUFACTURER);
        drugRegistry.createBatch(_medicineId, _batchId, _quantity, _productionDate, _expiryDate);

        // Register second medicine and batch
        string memory secondMedicineId = "M-IBU01";
        string memory secondBatchId = "B1-IBU01";

        vm.startPrank(MANUFACTURER);
        drugRegistry.registerMedicine(secondMedicineId, "345-4228-4232", "Ibuprofen", "Advil", _ingredients, _details);
        vm.stopPrank();

        vm.prank(REGULATOR);
        drugRegistry.approveMedicine(secondMedicineId);

        vm.prank(MANUFACTURER);
        drugRegistry.createBatch(secondMedicineId, secondBatchId, _quantity, _productionDate, _expiryDate);

        // Now check manufacturer has both medicineIds
        string[] memory manufacturerMedicineIds = supplyChainRegistry.getAddressMedicineIds(MANUFACTURER);

        assertEq(manufacturerMedicineIds.length, 2, "Should have two distinct medicineIds");

        // Check that both medicine IDs are present (order might vary)
        bool foundFirst = false;
        bool foundSecond = false;

        for (uint256 i = 0; i < manufacturerMedicineIds.length; i++) {
            if (keccak256(bytes(manufacturerMedicineIds[i])) == keccak256(bytes(_medicineId))) {
                foundFirst = true;
            }
            if (keccak256(bytes(manufacturerMedicineIds[i])) == keccak256(bytes(secondMedicineId))) {
                foundSecond = true;
            }
        }

        assertTrue(foundFirst, "First medicineId should be in the list");
        assertTrue(foundSecond, "Second medicineId should be in the list");

        console2.log("Manufacturer has multiple medicineIds: ", manufacturerMedicineIds.length);
        for (uint256 i = 0; i < manufacturerMedicineIds.length; i++) {
            console2.log("MedicineId ", i, ": ", manufacturerMedicineIds[i]);
        }
    }

    function test_MedicineIdRemovedOnCompleteTransfer() public registerAndApproveMedicine createBatch {
        // Transfer all inventory to supplier
        vm.prank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, SUPPLIER, _quantity);

        // Check that MANUFACTURER's inventory is now 0
        uint256 manufacturerInventory = supplyChainRegistry.getInventory(MANUFACTURER, _medicineId);
        assertEq(manufacturerInventory, 0, "Manufacturer inventory should be 0 after complete transfer");

        // Check that medicineId is removed from MANUFACTURER's list
        string[] memory manufacturerMedicineIds = supplyChainRegistry.getAddressMedicineIds(MANUFACTURER);
        bool found = false;
        for (uint256 i = 0; i < manufacturerMedicineIds.length; i++) {
            if (keccak256(bytes(manufacturerMedicineIds[i])) == keccak256(bytes(_medicineId))) {
                found = true;
                break;
            }
        }
        assertFalse(found, "MedicineId should be removed from manufacturer's list after complete transfer");

        // Check that SUPPLIER received the full inventory
        uint256 supplierInventory = supplyChainRegistry.getInventory(SUPPLIER, _medicineId);
        assertEq(supplierInventory, _quantity, "Supplier should have received the full inventory");
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

    function test_RevertWhenDispenseMoreThanAvailable() public registerAndApproveMedicine createBatch {
        // Transfer exactly 100 units to pharmacy
        vm.prank(MANUFACTURER);
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, 100);

        // Try to dispense 101 units (more than available)
        vm.prank(PHARMACY);
        vm.expectRevert(
            abi.encodeWithSelector(SupplyChainRegistry.SupplyChain__SenderHasInsufficientQuantity.selector, 101, 100)
        );
        supplyChainRegistry.dispenseMedicine(_batchId, 101, patientId);
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

    function test_GetEntityMedicines() public registerAndApproveMedicine createBatch {
        // Setup a second medicine and batch
        string memory secondMedicineId = "M-IBU01";
        string memory secondBatchId = "B1-IBU01";

        vm.prank(MANUFACTURER);
        drugRegistry.registerMedicine(secondMedicineId, "345-4228-4232", "Ibuprofen", "Advil", _ingredients, _details);

        vm.prank(REGULATOR);
        drugRegistry.approveMedicine(secondMedicineId);

        vm.prank(MANUFACTURER);
        drugRegistry.createBatch(
            secondMedicineId,
            secondBatchId,
            1000, // quantity
            _productionDate,
            _expiryDate
        );

        vm.startPrank(MANUFACTURER);
        // Transfer first medicine
        supplyChainRegistry.transferOwnership(_batchId, SUPPLIER, 500);
        supplyChainRegistry.transferOwnership(_batchId, PHARMACY, 300);

        // Transfer second medicine
        supplyChainRegistry.transferOwnership(secondBatchId, SUPPLIER, 200);
        supplyChainRegistry.transferOwnership(secondBatchId, PHARMACY, 150);
        vm.stopPrank();

        // Test manufacturer's medicines
        SupplyChainRegistry.MedicineDetails[] memory manufacturerMedicines =
            supplyChainRegistry.getEntityMedicines(MANUFACTURER);

        // Manufacturer should have two medicines
        assertEq(manufacturerMedicines.length, 2, "Manufacturer should have 2 medicine types");

        // Verify medicine details for manufacturer (quantities remaining after transfers)
        for (uint256 i = 0; i < manufacturerMedicines.length; i++) {
            if (keccak256(bytes(manufacturerMedicines[i].medicineId)) == keccak256(bytes(_medicineId))) {
                assertEq(manufacturerMedicines[i].medicineId, _medicineId);
                assertEq(manufacturerMedicines[i].batchId, _batchId);
                assertEq(manufacturerMedicines[i].name, _name);
                assertEq(manufacturerMedicines[i].brand, _brand);
                assertEq(manufacturerMedicines[i].remainingQuantity, 4000 - 500 - 300);
            } else {
                assertEq(manufacturerMedicines[i].medicineId, secondMedicineId);
                assertEq(manufacturerMedicines[i].batchId, secondBatchId);
                assertEq(manufacturerMedicines[i].name, "Ibuprofen");
                assertEq(manufacturerMedicines[i].brand, "Advil");
                assertEq(manufacturerMedicines[i].remainingQuantity, 1000 - 200 - 150);
            }
        }
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
