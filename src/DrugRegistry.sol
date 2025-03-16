// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGlobalRegistry} from "./GlobalRegistry.sol";

/**
 * @title DrugRegistry
 * @dev Manages medicine information, registrations, and supply chain tracking
 */
contract DrugRegistry {
    // ================ STRUCTS ================
    struct Medicine {
        string medicineId;
        string name;
        string brand;
        uint256 manufacturingDate;
        uint256 expiryDate;
        uint256 registrationDate;
        address manufacturer;
        string manufacturerId;
    }

    struct Batch {
        string batchId;
        string medicineId;
        string batchNumber;
        uint256 quantity;
        uint256 remainingQuantity;
        uint256 productionDate;
        bool isActive;
    }

    struct PharmacyStock {
        address pharmacyAddress;
        string pharmacyName;
        string location;
        uint256 availableQuantity;
    }

    enum EventType {
        MANUFACTURED,
        TO_SUPPLIER,
        TO_PHARMACY,
        DISPENSED
    }

    struct SupplyChainEvent {
        string medicineId;
        string batchId;
        EventType eventType;
        address fromEntity;
        address toEntity;
        uint256 quantity;
        uint256 timestamp;
        string patientId;
    }

    // ================ STATE VARIABLES ================
    IGlobalRegistry public globalRegistry;

    uint256 public medicineCounter;
    mapping(string => Medicine) public medicines;
    mapping(string => string) public medicineByName;

    mapping(string => Batch) public batches;
    mapping(string => string[]) public medicineBatches;

    mapping(string => SupplyChainEvent[]) public supplyChainEvents;
    mapping(string => SupplyChainEvent[]) public batchEvents;

    mapping(address => mapping(string => uint256)) public inventory;
    mapping(string => address[]) public medicineHolders;

    // ================ EVENTS ================
    event MedicineRegistered(string indexed medicineId, string name, address manufacturer);
    event BatchCreated(string batchId, string medicineId, uint256 quantity);
    event SupplierAuthorized(string medicineId, address supplier);
    event MedicineTransferred(string batchId, address from, address to, uint256 quantity);
    event MedicineDispensed(string batchId, address pharmacy, string patientId, uint256 quantity);

    // ================ MODIFIERS ================
    modifier onlyRole(IGlobalRegistry.Role role) {
        require(
            globalRegistry.verifyEntity(msg.sender) && globalRegistry.getEntityRole(msg.sender) == role,
            "DrugRegistry: caller does not have the required role"
        );
        _;
    }

    modifier medicineExists(string memory medicineId) {
        require(bytes(medicines[medicineId].medicineId).length > 0, "DrugRegistry: Medicine does not exist");
        _;
    }

    modifier batchExists(string memory batchId) {
        require(bytes(batches[batchId].batchId).length > 0, "DrugRegistry: Batch does not exist");
        _;
    }

    modifier onlyManufacturer(string memory medicineId) {
        require(
            medicines[medicineId].manufacturer == msg.sender, "DrugRegistry: Only manufacturer can perform this action"
        );
        _;
    }

    constructor(address globalRegistryAddress) {
        require(globalRegistryAddress != address(0), "Invalid global registry address");
        globalRegistry = IGlobalRegistry(globalRegistryAddress);
        medicineCounter = 0;
    }

    /**
     * @dev Register a new medicine
     * @param medicineId ID of the medicine
     * @param name Name of the medicine
     * @param brand Brand of the medicine
     * @param manufacturingDate Manufacturing date (Unix timestamp)
     * @param expiryDate Expiry date (Unix timestamp)
     * @return string ID of the newly registered medicine
     */
    function registerMedicine(
        string memory medicineId,
        string memory name,
        string memory brand,
        uint256 manufacturingDate,
        uint256 expiryDate
    ) public onlyRole(IGlobalRegistry.Role.MANUFACTURER) returns (string memory) {
        // FIXME: ADD CUSTOM ERRORS FOR EACH REQUIRE STATEMENT
        require(bytes(name).length > 0, "Medicine name cannot be empty");
        require(expiryDate > manufacturingDate, "Expiry date must be after manufacturing date");
        require(bytes(medicineByName[name]).length == 0, "Medicine with this name already exists");

        medicineCounter++;

        Medicine storage newMedicine = medicines[medicineId];
        newMedicine.medicineId = medicineId;
        newMedicine.name = name;
        newMedicine.brand = brand;
        newMedicine.manufacturingDate = manufacturingDate;
        newMedicine.expiryDate = expiryDate;
        newMedicine.registrationDate = block.timestamp;
        newMedicine.manufacturer = msg.sender;
        newMedicine.manufacturerId = globalRegistry.getManufacturerId(msg.sender);

        medicineByName[name] = medicineId;

        emit MedicineRegistered(medicineId, name, msg.sender);

        return medicineId;
    }

    /**
     * @dev Create a new batch of medicine
     * @param medicineId ID of the medicine
     * @param batchNumber Batch number
     * @param quantity Quantity of medicine in the batch
     * @param productionDate Production date (Unix timestamp)
     * @return string ID of the newly created batch
     */
    function createBatch(string memory medicineId, string memory batchNumber, uint256 quantity, uint256 productionDate)
        public
        medicineExists(medicineId)
        onlyManufacturer(medicineId)
        returns (string memory)
    {
        require(quantity > 0, "Quantity must be greater than zero");

        string memory batchId = string(abi.encodePacked(medicines[medicineId].name, "-", batchNumber));
        require(bytes(batches[batchId].batchId).length == 0, "Batch already exists");

        Batch storage newBatch = batches[batchId];
        newBatch.batchId = batchId;
        newBatch.medicineId = medicineId;
        newBatch.batchNumber = batchNumber;
        newBatch.quantity = quantity;
        newBatch.remainingQuantity = quantity;
        newBatch.productionDate = productionDate;
        newBatch.isActive = true;

        medicineBatches[medicineId].push(batchId);

        // Add to manufacturer's inventory
        inventory[msg.sender][medicineId] += quantity;
        if (inventory[msg.sender][medicineId] == quantity) {
            medicineHolders[medicineId].push(msg.sender);
        }

        // Record supply chain event
        SupplyChainEvent memory newEvent = SupplyChainEvent({
            medicineId: medicineId,
            batchId: batchId,
            eventType: EventType.MANUFACTURED,
            fromEntity: address(0),
            toEntity: msg.sender,
            quantity: quantity,
            timestamp: block.timestamp,
            patientId: ""
        });

        supplyChainEvents[medicineId].push(newEvent);
        batchEvents[batchId].push(newEvent);

        emit BatchCreated(batchId, medicineId, quantity);

        return batchId;
    }

    /**
     * @dev Transfer medicine to a supplier
     * @param batchId ID of the batch
     * @param supplierAddress Address of the supplier
     * @param quantity Quantity to transfer
     */
    function transferToSupplier(string memory batchId, address supplierAddress, uint256 quantity)
        public
        batchExists(batchId)
    {
        require(quantity > 0, "Quantity must be greater than zero");

        Batch storage batch = batches[batchId];
        string memory medicineId = batch.medicineId;

        require(batch.isActive && batch.remainingQuantity >= quantity, "Insufficient batch quantity");

        require(inventory[msg.sender][medicineId] >= quantity, "Insufficient inventory");

        require(
            globalRegistry.verifyEntity(supplierAddress)
                && globalRegistry.getEntityRole(supplierAddress) == IGlobalRegistry.Role.SUPPLIER,
            "Recipient is not a verified supplier"
        );

        // Update batch
        batch.remainingQuantity -= quantity;

        // Update inventories
        inventory[msg.sender][medicineId] -= quantity;
        inventory[supplierAddress][medicineId] += quantity;

        // Add supplier to medicine holders if this is their first stock
        if (inventory[supplierAddress][medicineId] == quantity) {
            medicineHolders[medicineId].push(supplierAddress);
        }

        // Record supply chain event
        SupplyChainEvent memory newEvent = SupplyChainEvent({
            medicineId: medicineId,
            batchId: batchId,
            eventType: EventType.TO_SUPPLIER,
            fromEntity: msg.sender,
            toEntity: supplierAddress,
            quantity: quantity,
            timestamp: block.timestamp,
            patientId: ""
        });

        supplyChainEvents[medicineId].push(newEvent);
        batchEvents[batchId].push(newEvent);

        emit MedicineTransferred(batchId, msg.sender, supplierAddress, quantity);
    }

    /**
     * @dev Transfer medicine to a pharmacy
     * @param batchId ID of the batch
     * @param pharmacyAddress Address of the pharmacy
     * @param quantity Quantity to transfer
     */
    function transferToPharmacy(string memory batchId, address pharmacyAddress, uint256 quantity)
        public
        batchExists(batchId)
    {
        require(quantity > 0, "Quantity must be greater than zero");

        Batch storage batch = batches[batchId];
        string memory medicineId = batch.medicineId;

        require(batch.isActive && batch.remainingQuantity >= quantity, "Insufficient batch quantity");

        require(inventory[msg.sender][medicineId] >= quantity, "Insufficient inventory");

        require(
            globalRegistry.verifyEntity(pharmacyAddress)
                && globalRegistry.getEntityRole(pharmacyAddress) == IGlobalRegistry.Role.PHARMACY,
            "Recipient is not a verified pharmacy"
        );

        // Only suppliers or manufacturers can transfer to pharmacies
        require(
            globalRegistry.getEntityRole(msg.sender) == IGlobalRegistry.Role.SUPPLIER
                || globalRegistry.getEntityRole(msg.sender) == IGlobalRegistry.Role.MANUFACTURER,
            "Only suppliers or manufacturers can transfer to pharmacies"
        );

        // Update batch
        batch.remainingQuantity -= quantity;

        // Update inventories
        inventory[msg.sender][medicineId] -= quantity;
        inventory[pharmacyAddress][medicineId] += quantity;

        // Add pharmacy to medicine holders if this is their first stock
        if (inventory[pharmacyAddress][medicineId] == quantity) {
            medicineHolders[medicineId].push(pharmacyAddress);
        }

        // Record supply chain event
        SupplyChainEvent memory newEvent = SupplyChainEvent({
            medicineId: medicineId,
            batchId: batchId,
            eventType: EventType.TO_PHARMACY,
            fromEntity: msg.sender,
            toEntity: pharmacyAddress,
            quantity: quantity,
            timestamp: block.timestamp,
            patientId: ""
        });

        supplyChainEvents[medicineId].push(newEvent);
        batchEvents[batchId].push(newEvent);

        emit MedicineTransferred(batchId, msg.sender, pharmacyAddress, quantity);
    }

    /**
     * @dev Dispense medicine to a patient
     * @param batchId ID of the batch
     * @param quantity Quantity to dispense
     */
    function dispenseMedicine(string memory batchId, uint256 quantity, string memory patientId)
        public
        batchExists(batchId)
        onlyRole(IGlobalRegistry.Role.PHARMACY)
    {
        require(quantity > 0, "Quantity must be greater than zero");
        require(bytes(patientId).length > 0, "Patient ID cannot be empty");

        Batch storage batch = batches[batchId];
        string memory medicineId = batch.medicineId;

        require(batch.isActive, "Batch is not active");

        require(inventory[msg.sender][medicineId] >= quantity, "Insufficient inventory");

        // Update inventories
        inventory[msg.sender][medicineId] -= quantity;

        // Record supply chain event
        SupplyChainEvent memory newEvent = SupplyChainEvent({
            medicineId: medicineId,
            batchId: batchId,
            eventType: EventType.DISPENSED,
            fromEntity: msg.sender,
            toEntity: address(0),
            quantity: quantity,
            timestamp: block.timestamp,
            patientId: patientId
        });

        supplyChainEvents[medicineId].push(newEvent);
        batchEvents[batchId].push(newEvent);

        emit MedicineDispensed(batchId, msg.sender, patientId, quantity);
    }
}
