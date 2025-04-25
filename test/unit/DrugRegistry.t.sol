// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DrugRegistry} from "../../src/DrugRegistry.sol";
import {IGlobalRegistry, GlobalRegistry} from "../../src/GlobalRegistry.sol";

contract DrugRegistryTest is Test {
    GlobalRegistry public globalRegistry;
    DrugRegistry public drugRegistry;

    address public supplyChainRegistryAddr = makeAddr("SupplyChainRegistry");

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

    function setUp() public {
        vm.startPrank(REGULATOR);
        globalRegistry = new GlobalRegistry();

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
        drugRegistry = new DrugRegistry(address(globalRegistry));
        console2.log("DrugRegistry address: ", address(drugRegistry));
        console2.log("GlobalRegistry address: ", address(globalRegistry));
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

    function test_RegisterMedicine() public {
        vm.prank(MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _serialNo, _name, _brand, _ingredients, _details);
        (
            string memory medicineId,
            ,
            string memory name,
            string memory brand,
            ,
            ,
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

    function test_RegulatorCanApproveMedicine() public {
        // register new medicine
        vm.prank(MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _serialNo, _name, _brand, _ingredients, _details);

        // approve registered medicine
        vm.prank(REGULATOR);
        drugRegistry.approveMedicine(_medicineId);

        (string memory medicineId,,,,,,,,, bool approved) = drugRegistry.getMedicineDetailsById(_medicineId);
        assertTrue(approved);

        console2.log("Medicine Id: ", medicineId);
        console2.log("Approved: ", approved);
    }

    function test_ManufacturerCanCreateBatch() public registerAndApproveMedicine {
        vm.prank(MANUFACTURER);
        drugRegistry.createBatch(_medicineId, _batchId, _quantity, _productionDate, _expiryDate);

        bool batchExists = drugRegistry.verifyBatch(_batchId);
        assertTrue(batchExists);
        console2.log("New batch created!\n  Batch ID: ", _batchId);
    }

    function test_DeactivateExpiredBatch() public registerAndApproveMedicine createBatch {
        // set timestamp to 2 years in the future
        vm.warp(block.timestamp + interval + 1);
        //  Set block.number
        vm.roll(block.number + 1);

        vm.expectEmit(true, false, false, true);
        emit DrugRegistry.BatchDeactivated(_batchId, "Expired");
        drugRegistry.deactivateExpiredBatch();

        // check if batch is deactivated
        DrugRegistry.Batch memory batch = drugRegistry.getBatchDetails(_batchId);
        assertFalse(batch.isActive);
        console2.log("Batch status: ", batch.isActive);
        console2.log("Current block.timestamp: ", block.timestamp);
        console2.log("Batch expiry date: ", batch.expiryDate);
    }

    function test_ManufacturerCanDeactivateBatch() public registerAndApproveMedicine createBatch {
        vm.prank(MANUFACTURER);
        drugRegistry.deactivateBatch(_batchId, _medicineId);

        bool isActive = drugRegistry.isBatchActive(_batchId);
        assertFalse(isActive);
    }

    function test_verifyMedicine() public registerAndApproveMedicine {
        bool validMedicine = drugRegistry.verifyMedicine(_medicineId);
        bool invalidMedicine = drugRegistry.verifyMedicine("M-REU22");

        assertTrue(validMedicine);
        assertFalse(invalidMedicine);
    }

    function test_verifyBatch() public registerAndApproveMedicine createBatch {
        bool validBatch = drugRegistry.verifyBatch(_batchId);
        bool invalidBatch = drugRegistry.verifyBatch("B-REU222");

        assertTrue(validBatch);
        assertFalse(invalidBatch);
    }

    function test_RequireMedicineExists() public {
        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__MedicineExistenceStatus.selector, _medicineId, false)
        );
        drugRegistry.requireMedicineExists(_medicineId);
    }

    function test_RequireBatchExists() public {
        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__BatchExistenceStatus.selector, _batchId, false)
        );
        drugRegistry.requireBatchExists(_batchId);
    }

    function test_GetMedicineIds() public registerAndApproveMedicine {
        // Register another medicine to have at least 2 medicines
        string memory secondMedicineId = "M-PAE02";
        vm.prank(MANUFACTURER);
        drugRegistry.registerMedicine(secondMedicineId, "345-4228-4232", "Ibuprofen", "Advil", _ingredients, _details);

        // Get all medicine IDs
        string[] memory medicineIds = drugRegistry.getMedicineIds();

        // Assertions
        assertEq(medicineIds.length, 2);
        assertEq(medicineIds[0], _medicineId);
        assertEq(medicineIds[1], secondMedicineId);

        // Log for visibility
        console2.log("Medicine count:", medicineIds.length);
        for (uint256 i = 0; i < medicineIds.length; i++) {
            console2.log("Medicine ID at index", i, ":", medicineIds[i]);
        }
    }

    function test_GetBatchIds() public registerAndApproveMedicine createBatch {
        // Create another batch to have at least 2 batches
        string memory secondBatchId = "B1-PAE02";
        vm.prank(MANUFACTURER);
        drugRegistry.createBatch(_medicineId, secondBatchId, _quantity, _productionDate, _expiryDate);

        // Get all batch IDs
        string[] memory batchIds = drugRegistry.getBatchIds();

        // Assertions
        assertEq(batchIds.length, 2);
        assertEq(batchIds[0], _batchId);
        assertEq(batchIds[1], secondBatchId);

        // Log for visibility
        console2.log("Batch count:", batchIds.length);
        for (uint256 i = 0; i < batchIds.length; i++) {
            console2.log("Batch ID at index", i, ":", batchIds[i]);
        }
    }

    // =========================== REVERTS ===========================

    function test_RevertMedicineRegistrationWithMinLengthRequirement() public {
        string memory name = "P";

        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DrugRegistry.DrugRegistry__MinLengthRequired.selector, "Medicine Name", bytes(name).length, 2
            )
        );
        drugRegistry.registerMedicine(_medicineId, _serialNo, name, _brand, _ingredients, _details);
    }

    function test_RevertWithSenderIsNotAuthorizedToPerformAction() public {
        vm.startPrank(MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _serialNo, _name, _brand, _ingredients, _details);

        vm.expectRevert(abi.encodeWithSelector(DrugRegistry.DrugRegistry__SenderIsNotAuthorized.selector, MANUFACTURER));
        drugRegistry.approveMedicine(_medicineId);
        vm.stopPrank();
    }

    function test_RevertWithMedicineDoesNotExist() public {
        // attempt to approve a medicine that hasn't been registered
        vm.prank(REGULATOR);
        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__MedicineExistenceStatus.selector, _medicineId, false)
        );
        drugRegistry.approveMedicine(_medicineId);
    }

    function test_RevertWithMedicineAlreadyExists() public registerAndApproveMedicine {
        // attempt to register a medicine that has already been registered
        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__MedicineExistenceStatus.selector, _medicineId, true)
        );
        drugRegistry.registerMedicine(_medicineId, _serialNo, _name, _brand, _ingredients, _details);
    }

    function test_RevertWithBatchAlreadyExists() public registerAndApproveMedicine createBatch {
        // attempt to create a batch with the same batchId
        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__BatchExistenceStatus.selector, _batchId, true)
        );
        drugRegistry.createBatch(_medicineId, _batchId, _quantity, _productionDate, _expiryDate);
        console2.log("Batch already exists!");
    }

    function test_RevertWithBatchDoesNotExist() public {
        // attempt to transfer a batch that does not exist
        vm.prank(MANUFACTURER);
        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__BatchExistenceStatus.selector, _batchId, false)
        );
        drugRegistry.isBatchActive(_batchId);
    }

    function test_RevertWithMedicineIsAlreadyApproved() public registerAndApproveMedicine {
        vm.prank(REGULATOR);
        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__MedicineApprovalStatus.selector, _medicineId, true)
        );
        drugRegistry.approveMedicine(_medicineId);
    }

    function test_RevertWithMedicineNotApproved() public {
        vm.startPrank(MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _serialNo, _name, _brand, _ingredients, _details);

        vm.expectRevert(
            abi.encodeWithSelector(DrugRegistry.DrugRegistry__MedicineApprovalStatus.selector, _medicineId, false)
        );
        drugRegistry.createBatch(_medicineId, _batchId, _quantity, _productionDate, _expiryDate);
        vm.stopPrank();
    }

    // =========================== GETTER FUNCTIONS ===========================
    function test_GetMedicineDetailsById() public registerAndApproveMedicine {
        (
            string memory medicineId,
            ,
            string memory name,
            string memory brand,
            ,
            ,
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

    function test_GetBatchDetails() public registerAndApproveMedicine createBatch {
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

    function test_GetMedicineBatches() public registerAndApproveMedicine createBatch {
        // Create 2nd batch
        vm.prank(MANUFACTURER);
        drugRegistry.createBatch(_medicineId, "B1-PAE02", _quantity, _productionDate, _expiryDate);

        string[] memory batchIds = drugRegistry.getMedicineBatches(_medicineId);

        assertEq(batchIds.length, 2);
        for (uint256 i = 0; i < batchIds.length; i++) {
            console2.log("Batch ID: ", batchIds[i]);
        }
    }

    function test_GetBatchCount() public registerAndApproveMedicine createBatch {
        // Create 2nd batch
        vm.prank(MANUFACTURER);
        drugRegistry.createBatch(_medicineId, "B1-PAE02", _quantity, _productionDate, _expiryDate);

        uint256 batchCount = drugRegistry.getBatchCount();
        assertEq(batchCount, 2);
    }

    function test_getMedicineCount() public registerAndApproveMedicine {
        uint256 count = drugRegistry.getMedicineCount();
        assertNotEq(count, 0);
    }

    function test_GetMedicineManufacturer() public registerAndApproveMedicine createBatch {
        address manufacturer = drugRegistry.getMedicineManufacturer(_medicineId);
        assertEq(manufacturer, MANUFACTURER);
    }

    // =========================== EVENTS ===========================
    function test_EmitsMedicineRegistered() public {
        vm.prank(MANUFACTURER);
        vm.expectEmit(true, false, false, true);
        emit DrugRegistry.MedicineRegistered(_medicineId, _name, MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _serialNo, _name, _brand, _ingredients, _details);
    }

    function test_EmitsMedicineApproved() public {
        vm.prank(MANUFACTURER);
        drugRegistry.registerMedicine(_medicineId, _serialNo, _name, _brand, _ingredients, _details);

        vm.prank(REGULATOR);
        vm.expectEmit(true, false, false, true);
        emit DrugRegistry.MedicineApproved(_medicineId, MANUFACTURER);
        drugRegistry.approveMedicine(_medicineId);
    }

    function test_EmitsBatchCreated() public registerAndApproveMedicine {
        vm.prank(MANUFACTURER);
        vm.expectEmit(true, false, false, true);
        emit DrugRegistry.BatchCreated(_batchId, _medicineId, _quantity);
        drugRegistry.createBatch(_medicineId, _batchId, _quantity, _productionDate, _expiryDate);
    }

    function test_EmitsSupplyRegistrySet() public {
        vm.prank(REGULATOR);
        vm.expectEmit(false, false, false, true);
        emit DrugRegistry.SupplyChainRegistrySet(supplyChainRegistryAddr);
        drugRegistry.setSupplyChainRegistry(supplyChainRegistryAddr);
    }

    function test_EmitsBatchDeactivated() public registerAndApproveMedicine createBatch {
        vm.prank(MANUFACTURER);
        vm.expectEmit(true, false, false, true);
        emit DrugRegistry.BatchDeactivated(_batchId, "Deactivated by Manufacturer");
        drugRegistry.deactivateBatch(_batchId, _medicineId);
    }
}
