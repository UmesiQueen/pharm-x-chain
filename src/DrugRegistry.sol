// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGlobalRegistry} from "./GlobalRegistry.sol";
/**
 * @title DrugRegistry
 * @dev Manages medicine information, registrations, and supply chain tracking
 */

contract DrugRegistry {
    // ================ ERRORS =================
    error DrugRegistry__NotAuthorizedToPerformAction(IGlobalRegistry.Role role, IGlobalRegistry.Role optRole);
    error DrugRegistry__MedicineExistenceStatus(string medicineId, bool exists);
    error DrugRegistry__BatchExistenceStatus(string batchId, bool exists);
    error DrugRegistry__BatchIsNotActive(string batchId);
    error DrugRegistry__InvalidGlobalRegistryContractAddress(address globalRegistryAddress);
    error DrugRegistry__MedicineApprovalStatus(string medicineId, bool approved);
    error DrugRegistry__InsufficientInventoryQuantity(uint256 requestedQuantity, uint256 availableQuantity);
    error DrugRegistry__InsufficientBatchQuantity(uint256 requestedQuantity, uint256 availableQuantity);
    error DrugRegistry__MinLengthRequired(string field, uint256 givenLength, uint256 minLength);

    // ================ STRUCTS ================

    struct Medicine {
        string medicineId;
        string name;
        string brand;
        uint256 registrationDate;
        address manufacturer;
        string manufacturerId;
        bool approved;
    }

    struct Batch {
        string batchId;
        string medicineId;
        uint256 quantity;
        uint256 remainingQuantity;
        uint256 productionDate;
        uint256 expiryDate;
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
    event MedicineApproved(string medicineId);
    event BatchCreated(string batchId, string medicineId, uint256 quantity);
    event BatchDeactivated(string batchId, string reason);
    event MedicineTransferred(string batchId, address from, address to, uint256 quantity);
    event MedicineDispensed(string batchId, address pharmacy, string patientId, uint256 quantity);
    // TODO: Implement low inventory alert
    event LowInventoryAlert(string batchId, string name, uint256 quantity);

    // ================ MODIFIERS ================
    modifier onlyRole(IGlobalRegistry.Role role) {
        if (!globalRegistry.verifyEntity(msg.sender) && globalRegistry.getEntityRole(msg.sender) != role) {
            revert DrugRegistry__NotAuthorizedToPerformAction(role, IGlobalRegistry.Role.NONE);
        }
        _;
    }

    modifier medicineExists(string memory medicineId) {
        if (bytes(medicines[medicineId].medicineId).length == 0) {
            revert DrugRegistry__MedicineExistenceStatus(medicineId, false);
        }
        _;
    }

    modifier batchExists(string memory batchId) {
        if (bytes(batches[batchId].batchId).length == 0) {
            revert DrugRegistry__BatchExistenceStatus(batchId, false);
        }
        _;
    }

    modifier onlyManufacturer(string memory medicineId) {
        if (medicines[medicineId].manufacturer != msg.sender) {
            revert DrugRegistry__NotAuthorizedToPerformAction(
                IGlobalRegistry.Role.MANUFACTURER, IGlobalRegistry.Role.NONE
            );
        }
        _;
    }

    constructor(address globalRegistryAddress) {
        if (globalRegistryAddress == address(0)) {
            revert DrugRegistry__InvalidGlobalRegistryContractAddress(globalRegistryAddress);
        }
        globalRegistry = IGlobalRegistry(globalRegistryAddress);
        medicineCounter = 0;
    }

    /**
     * @dev Register a new medicine
     * @param medicineId ID of the medicine
     * @param name Name of the medicine
     * @param brand Brand of the medicine
     * @return string ID of the newly registered medicine
     */
    function registerMedicine(string memory medicineId, string memory name, string memory brand)
        public
        onlyRole(IGlobalRegistry.Role.MANUFACTURER)
        returns (string memory)
    {
        if (bytes(name).length < 2) {
            revert DrugRegistry__MinLengthRequired("Medicine Name", bytes(name).length, 2);
        } else if (bytes(brand).length < 2) {
            revert DrugRegistry__MinLengthRequired("Medicine Brand", bytes(brand).length, 2);
        }

        medicineCounter++;

        Medicine storage newMedicine = medicines[medicineId];
        newMedicine.medicineId = medicineId;
        newMedicine.name = name;
        newMedicine.brand = brand;
        newMedicine.registrationDate = block.timestamp;
        newMedicine.manufacturer = msg.sender;
        newMedicine.manufacturerId = globalRegistry.getManufacturerId(msg.sender);
        newMedicine.approved = false;

        // FIXME: There are no checks of if the medicine name already exists, else, make it an array.
        medicineByName[name] = medicineId;

        emit MedicineRegistered(medicineId, name, msg.sender);

        return medicineId;
    }

    /**
     * @dev Approve a medicine by regulator
     * @param medicineId ID of the medicine
     */
    function approveMedicine(string memory medicineId)
        public
        onlyRole(IGlobalRegistry.Role.REGULATOR)
        medicineExists(medicineId)
    {
        if (medicines[medicineId].approved) {
            revert DrugRegistry__MedicineApprovalStatus(medicineId, true);
        }

        medicines[medicineId].approved = true;
        emit MedicineApproved(medicineId);
    }

    /**
     * @dev Create a new batch of medicine
     * @param medicineId ID of the medicine
     * @param batchId ID of the batch
     * @param quantity Quantity of medicine in the batch
     * @param productionDate Production date (Unix timestamp)
     * @param expiryDate Expiry date (Unix timestamp)
     * @return string ID of the newly created batch
     */
    function createBatch(
        string memory medicineId,
        string memory batchId,
        uint256 quantity,
        uint256 productionDate,
        uint256 expiryDate
    ) public medicineExists(medicineId) onlyManufacturer(medicineId) returns (string memory) {
        if (!medicines[medicineId].approved) {
            revert DrugRegistry__MedicineApprovalStatus(medicineId, false);
        }
        if (quantity <= 0) {
            revert DrugRegistry__MinLengthRequired("Medicine Quantity", quantity, 1);
        }
        require(expiryDate > productionDate, "Expiry date must be after manufacturing date");

        if (bytes(batches[batchId].batchId).length != 0) {
            revert DrugRegistry__BatchExistenceStatus(batchId, true);
        }

        Batch storage newBatch = batches[batchId];
        newBatch.batchId = batchId;
        newBatch.medicineId = medicineId;
        newBatch.quantity = quantity;
        newBatch.remainingQuantity = quantity;
        newBatch.productionDate = productionDate;
        newBatch.expiryDate = expiryDate;
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
        // Only registered suppliers can receive medicine
        if (
            !globalRegistry.verifyEntity(supplierAddress)
                && globalRegistry.getEntityRole(supplierAddress) != IGlobalRegistry.Role.SUPPLIER
        ) {
            revert DrugRegistry__NotAuthorizedToPerformAction(IGlobalRegistry.Role.SUPPLIER, IGlobalRegistry.Role.NONE);
        }

        // Check if the quantity is valid
        if (quantity <= 0) {
            revert DrugRegistry__MinLengthRequired("Medicine Quantity", quantity, 1);
        }

        Batch storage batch = batches[batchId];
        string memory medicineId = batch.medicineId;

        // Check if the batch is active
        if (!batch.isActive) {
            revert DrugRegistry__BatchIsNotActive(batchId);
        }

        // Check if the sender is the manufacturer, and if so, update the batch
        if (medicines[medicineId].manufacturer == msg.sender) {
            // Check if the batch has enough quantity
            uint256 batchRemainingQuantity = batch.remainingQuantity;
            if (batchRemainingQuantity < quantity) {
                revert DrugRegistry__InsufficientBatchQuantity(quantity, batchRemainingQuantity);
            }
            // Update batch
            batchRemainingQuantity -= quantity;
        }

        // Check if the pharmacy has enough quantity
        uint256 inventoryQuantity = inventory[msg.sender][medicineId];
        if (inventoryQuantity < quantity) {
            revert DrugRegistry__InsufficientInventoryQuantity(quantity, inventoryQuantity);
        }

        // Update inventories
        inventoryQuantity -= quantity;
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
        // Only registered pharmacies can receive medicine
        if (
            !globalRegistry.verifyEntity(pharmacyAddress)
                && globalRegistry.getEntityRole(pharmacyAddress) != IGlobalRegistry.Role.PHARMACY
        ) {
            revert DrugRegistry__NotAuthorizedToPerformAction(IGlobalRegistry.Role.PHARMACY, IGlobalRegistry.Role.NONE);
        }

        // Only suppliers or manufacturers can transfer to pharmacies
        if (
            globalRegistry.getEntityRole(msg.sender) != IGlobalRegistry.Role.SUPPLIER
                || globalRegistry.getEntityRole(msg.sender) != IGlobalRegistry.Role.MANUFACTURER
        ) {
            revert DrugRegistry__NotAuthorizedToPerformAction(
                IGlobalRegistry.Role.SUPPLIER, IGlobalRegistry.Role.MANUFACTURER
            );
        }
        // Check if the quantity is valid
        if (quantity <= 0) {
            revert DrugRegistry__MinLengthRequired("Medicine Quantity", quantity, 1);
        }

        Batch storage batch = batches[batchId];
        string memory medicineId = batch.medicineId;

        // Check if the batch is active
        if (!batch.isActive) {
            revert DrugRegistry__BatchIsNotActive(batchId);
        }

        // Check if the sender is the manufacturer, and if so, update the batch
        if (medicines[medicineId].manufacturer == msg.sender) {
            // Check if the batch has enough quantity
            uint256 batchRemainingQuantity = batch.remainingQuantity;
            if (batchRemainingQuantity < quantity) {
                revert DrugRegistry__InsufficientBatchQuantity(quantity, batchRemainingQuantity);
            }
            // Update batch
            batchRemainingQuantity -= quantity;
        }

        // Check if the sender has enough quantity
        uint256 inventoryQuantity = inventory[msg.sender][medicineId];
        if (inventoryQuantity < quantity) {
            revert DrugRegistry__InsufficientInventoryQuantity(quantity, inventoryQuantity);
        }

        // Update inventories
        inventoryQuantity -= quantity;
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
        if (quantity <= 0) {
            revert DrugRegistry__MinLengthRequired("Medicine Quantity", quantity, 1);
        }
        require(bytes(patientId).length > 0, "Patient ID cannot be empty");

        Batch storage batch = batches[batchId];
        string memory medicineId = batch.medicineId;

        // Check if the batch is active
        if (!batch.isActive) {
            revert DrugRegistry__BatchIsNotActive(batchId);
        }

        // Check if the pharmacy has enough quantity
        uint256 inventoryQuantity = inventory[msg.sender][medicineId];
        if (inventoryQuantity < quantity) {
            revert DrugRegistry__InsufficientInventoryQuantity(quantity, inventoryQuantity);
        }

        // Update inventories
        inventoryQuantity -= quantity;

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

    /**
     * @dev Get medicine details by ID
     * @param _medicineId ID of the medicine
     * @return medicineId ID of the medicine
     * @return name Name of the medicine
     * @return brand Brand of the medicine
     * @return registrationDate Registration date (Unix timestamp)
     * @return manufacturer Address of manufacturer
     * @return manufacturerId ID of the manufacturer
     * @return approved Approval status of the medicine
     */
    function getMedicineDetailsById(string memory _medicineId)
        public
        view
        medicineExists(_medicineId)
        returns (
            string memory medicineId,
            string memory name,
            string memory brand,
            uint256 registrationDate,
            address manufacturer,
            string memory manufacturerId,
            bool approved
        )
    {
        Medicine storage medicine = medicines[_medicineId];

        return (
            medicine.medicineId,
            medicine.name,
            medicine.brand,
            medicine.registrationDate,
            medicine.manufacturer,
            medicine.manufacturerId,
            medicine.approved
        );
    }

    /**
     * @dev Get medicine details by name
     * @param medicineName Name of the medicine
     * @return Medicine struct containing medicine details
     */
    function getMedicineDetailsByName(string memory medicineName) public view returns (Medicine memory) {
        string memory medicineId = medicineByName[medicineName];
        if (bytes(medicineId).length == 0) {
            revert DrugRegistry__MedicineExistenceStatus(medicineId, false);
        }
        return medicines[medicineId];
    }

    /**
     * @dev Get batch details
     * @param batchId ID of the batch
     * @return Batch struct containing batch details
     */
    function getBatchDetails(string memory batchId) public view batchExists(batchId) returns (Batch memory) {
        return batches[batchId];
    }

    /**
     * @dev Get inventory of a specific medicine at an entity
     * @param entityAddress Address of the entity
     * @param medicineId ID of the medicine
     * @return uint256 Quantity of medicine in inventory
     */
    function getInventory(address entityAddress, string memory medicineId) public view returns (uint256) {
        return inventory[entityAddress][medicineId];
    }

    /**
     * @dev Get list of pharmacies with available stock of a specific medicine
     * @param medicineId ID of the medicine
     * @return PharmacyStock[] Array of PharmacyStock structs
     */
    function getPharmacyAvailability(string memory medicineId)
        public
        view
        medicineExists(medicineId)
        returns (PharmacyStock[] memory)
    {
        address[] memory holders = medicineHolders[medicineId];
        uint256 pharmacyCount = 0;

        // Count pharmacies with stock
        for (uint256 i = 0; i < holders.length; i++) {
            if (
                globalRegistry.verifyEntity(holders[i])
                    && globalRegistry.getEntityRole(holders[i]) == IGlobalRegistry.Role.PHARMACY
                    && inventory[holders[i]][medicineId] > 0
            ) {
                pharmacyCount++;
            }
        }

        PharmacyStock[] memory result = new PharmacyStock[](pharmacyCount);
        uint256 resultIndex = 0;

        // Populate result array
        for (uint256 i = 0; i < holders.length; i++) {
            if (
                globalRegistry.verifyEntity(holders[i])
                    && globalRegistry.getEntityRole(holders[i]) == IGlobalRegistry.Role.PHARMACY
                    && inventory[holders[i]][medicineId] > 0
            ) {
                (string memory name, string memory location,,,,) = globalRegistry.getEntityDetails(holders[i]);

                result[resultIndex] = PharmacyStock({
                    pharmacyAddress: holders[i],
                    pharmacyName: name,
                    location: location,
                    availableQuantity: inventory[holders[i]][medicineId]
                });

                resultIndex++;
            }
        }

        return result;
    }

    /**
     * @dev Get complete supply chain history of a medicine
     * @param medicineId ID of the medicine
     * @return SupplyChainEvent[] Array of SupplyChainEvent structs
     */
    function getSupplyChainHistory(string memory medicineId)
        public
        view
        medicineExists(medicineId)
        returns (SupplyChainEvent[] memory)
    {
        return supplyChainEvents[medicineId];
    }

    /**
     * @dev Verify authenticity of a medicine
     * @param medicineId ID of the medicine
     * @return bool True if medicine is authentic
     */
    function verifyAuthenticity(string memory medicineId) public view returns (bool) {
        // Medicine exists and has supply chain events
        if (
            keccak256(bytes(medicines[medicineId].medicineId)) != keccak256(bytes(medicineId))
                || supplyChainEvents[medicineId].length == 0
        ) {
            return false;
        }

        // Check that the first event is MANUFACTURED
        if (supplyChainEvents[medicineId][0].eventType != EventType.MANUFACTURED) {
            return false;
        }

        // Check that the manufacturer in the event matches the registered manufacturer
        if (supplyChainEvents[medicineId][0].toEntity != medicines[medicineId].manufacturer) {
            return false;
        }

        return true;
    }

    /**
     * @dev Get all batches of a medicine
     * @param medicineId ID of the medicine
     * @return string[] Array of batch IDs
     */
    function getMedicineBatches(string memory medicineId)
        public
        view
        medicineExists(medicineId)
        returns (string[] memory)
    {
        return medicineBatches[medicineId];
    }

    /**
     * @dev Get supply chain events for a specific batch
     * @param batchId ID of the batch
     * @return SupplyChainEvent[] Array of SupplyChainEvent structs
     */
    function getBatchEvents(string memory batchId)
        public
        view
        batchExists(batchId)
        returns (SupplyChainEvent[] memory)
    {
        return batchEvents[batchId];
    }

    // TODO: Use Chainlink Automation to deactivate batches after expiry date
    function deactivateBatch(string memory batchId) public {
        Batch storage batch = batches[batchId];
        if (batch.expiryDate < block.timestamp) {
            batch.isActive = false;
        }
    }
}
