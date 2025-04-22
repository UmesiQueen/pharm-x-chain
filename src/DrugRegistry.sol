// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGlobalRegistry} from "./GlobalRegistry.sol";
/**
 * @title DrugRegistry
 * @dev Manages medicine information, registrations, and supply chain tracking
 */

contract DrugRegistry {
    // ================ ERRORS =================
    error DrugRegistry__SenderIsNotAuthorized(address sender);
    error DrugRegistry__ReceiverIsNotEligible(address receiver);
    error DrugRegistry__MedicineExistenceStatus(string medicineId, bool exists);
    error DrugRegistry__BatchExistenceStatus(string batchId, bool exists);
    error DrugRegistry__BatchIsNotActive(string batchId);
    error DrugRegistry__InvalidGlobalRegistryContractAddress(address globalRegistryAddress);
    error DrugRegistry__MedicineApprovalStatus(string medicineId, bool approved);
    error DrugRegistry__SenderHasInsufficientQuantity(uint256 requestedQuantity, uint256 availableQuantity);
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
        string batchId;
        address pharmacyAddress;
        string pharmacyName;
        string pharmacyLocation;
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

    string[] public medicineIds;
    string[] public batchIds;

    mapping(string => Medicine) public medicines;
    mapping(string => Batch) public batches;
    mapping(string => string[]) public medicineBatches;

    mapping(string => SupplyChainEvent[]) public supplyChainEvents;
    mapping(string => SupplyChainEvent[]) public batchEvents;

    mapping(address => mapping(string => uint256)) public inventory;

    // Define a struct to hold both address and batchID
    struct MedicineHolder {
        address holderAddress;
        string batchId; // Or use uint if your batchID is numeric
    }

    mapping(string => MedicineHolder[]) public medicineHolders;

    // ================ EVENTS ================
    event MedicineRegistered(string indexed medicineId, string name, address manufacturer);
    event MedicineApproved(string indexed medicineId, address manufacturer);
    event BatchCreated(string indexed batchId, string medicineId, uint256 quantity);
    event BatchDeactivated(string indexed batchId, string reason);
    event MedicineTransferred(string indexed batchId, address indexed from, address indexed to, uint256 quantity);
    event MedicineDispensed(
        string indexed batchId, address indexed pharmacy, string indexed patientId, uint256 quantity
    );
    event LowInventoryAlert(address indexed medicineHolder, string indexed batchId, uint256 indexed quantity);

    // ================ MODIFIERS ================
    modifier onlyRole(IGlobalRegistry.Role role) {
        if (!globalRegistry.verifyEntity(msg.sender) || globalRegistry.getEntityRole(msg.sender) != role) {
            revert DrugRegistry__SenderIsNotAuthorized(msg.sender);
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
            revert DrugRegistry__SenderIsNotAuthorized(msg.sender);
        }
        _;
    }

    constructor(address globalRegistryAddress) {
        if (globalRegistryAddress == address(0)) {
            revert DrugRegistry__InvalidGlobalRegistryContractAddress(globalRegistryAddress);
        }
        globalRegistry = IGlobalRegistry(globalRegistryAddress);
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

        // check if the medicineId already exists
        if (bytes(medicines[medicineId].medicineId).length != 0) {
            revert DrugRegistry__MedicineExistenceStatus(medicineId, true);
        }

        Medicine storage newMedicine = medicines[medicineId];
        newMedicine.medicineId = medicineId;
        newMedicine.name = name;
        newMedicine.brand = brand;
        newMedicine.registrationDate = block.timestamp;
        newMedicine.manufacturer = msg.sender;
        newMedicine.manufacturerId = globalRegistry.getManufacturerId(msg.sender);
        newMedicine.approved = false;

        // Add to the list of registered medicines
        medicineIds.push(medicineId);

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

        address manufacturer = medicines[medicineId].manufacturer;
        emit MedicineApproved(medicineId, manufacturer);
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
            MedicineHolder memory newHolder = MedicineHolder({holderAddress: msg.sender, batchId: batchId});
            medicineHolders[medicineId].push(newHolder);
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
        batchIds.push(batchId);

        emit BatchCreated(batchId, medicineId, quantity);

        return batchId;
    }

    /**
     * @dev Transfer ownership of medicine
     * @param batchId ID of the batch
     * @param entityAddress Address of entity
     * @param quantity Quantity to transfer
     */
    function transferOwnership(string memory batchId, address entityAddress, uint256 quantity)
        public
        batchExists(batchId)
    {
        // only registered entities can make transfers
        if (!globalRegistry.verifyEntity(msg.sender)) {
            revert DrugRegistry__SenderIsNotAuthorized(msg.sender);
        }

        IGlobalRegistry.Role role;
        // verify receiver's address and role
        if (globalRegistry.verifyEntity(entityAddress)) {
            IGlobalRegistry.Role entityRole = globalRegistry.getEntityRole(entityAddress);

            // cannot make transfer to regulator
            if (entityRole != IGlobalRegistry.Role.REGULATOR) {
                role = entityRole;
            } else {
                revert DrugRegistry__ReceiverIsNotEligible(entityAddress);
            }
        } else {
            revert DrugRegistry__ReceiverIsNotEligible(entityAddress);
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
                revert DrugRegistry__SenderHasInsufficientQuantity(quantity, batchRemainingQuantity);
            }
            // Update batch
            batch.remainingQuantity -= quantity;
        }

        // Check if the sender has enough quantity
        uint256 inventoryQuantity = inventory[msg.sender][medicineId];
        if (inventoryQuantity < quantity) {
            revert DrugRegistry__SenderHasInsufficientQuantity(quantity, inventoryQuantity);
        }

        // Update inventories
        inventory[msg.sender][medicineId] -= quantity;
        inventory[entityAddress][medicineId] += quantity;

        // emit low stock event if quantity is less than 10
        uint256 sendersInventory = inventory[msg.sender][medicineId];
        if (sendersInventory <= 10) {
            emit LowInventoryAlert(msg.sender, batchId, sendersInventory);
        }

        // Add entity to medicine holders if this is their first stock
        if (inventory[entityAddress][medicineId] == quantity) {
            MedicineHolder memory newHolder = MedicineHolder({holderAddress: entityAddress, batchId: batchId});
            medicineHolders[medicineId].push(newHolder);
        }

        // get event type based on receiver's role
        EventType eventType = getEventType(role);

        // Record supply chain event
        SupplyChainEvent memory newEvent = SupplyChainEvent({
            medicineId: medicineId,
            batchId: batchId,
            eventType: eventType,
            fromEntity: msg.sender,
            toEntity: entityAddress,
            quantity: quantity,
            timestamp: block.timestamp,
            patientId: ""
        });

        supplyChainEvents[medicineId].push(newEvent);
        batchEvents[batchId].push(newEvent);

        emit MedicineTransferred(batchId, msg.sender, entityAddress, quantity);
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
            revert DrugRegistry__SenderHasInsufficientQuantity(quantity, inventoryQuantity);
        }

        // Update inventories
        inventory[msg.sender][medicineId] -= quantity;

        // emit low stock event if quantity is less than 10
        uint256 sendersInventory = inventory[msg.sender][medicineId];
        if (sendersInventory <= 10) {
            emit LowInventoryAlert(msg.sender, batchId, sendersInventory);
        }

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
    function getPharmacyAvailability(string calldata medicineId)
        public
        view
        medicineExists(medicineId)
        returns (PharmacyStock[] memory)
    {
        MedicineHolder[] storage holders = medicineHolders[medicineId];
        uint256 holdersLength = holders.length;

        // First count valid pharmacies to size our array properly
        uint256 pharmacyCount = 0;
        for (uint256 i = 0; i < holdersLength; i++) {
            address holderAddress = holders[i].holderAddress;
            Batch storage batch = batches[holders[i].batchId]; // get and check that batch is active
            if (
                globalRegistry.verifyEntity(holderAddress)
                    && globalRegistry.getEntityRole(holderAddress) == IGlobalRegistry.Role.PHARMACY
                    && inventory[holderAddress][medicineId] > 0 && batch.isActive
            ) {
                pharmacyCount++;
            }
        }

        // If no pharmacies have stock, return early
        if (pharmacyCount == 0) {
            return new PharmacyStock[](0);
        }

        PharmacyStock[] memory result = new PharmacyStock[](pharmacyCount);

        // Only if we have results to return, do the second loop
        uint256 resultIndex = 0;
        for (uint256 i = 0; i < holdersLength; i++) {
            address holderAddress = holders[i].holderAddress;
            uint256 medicineStock = inventory[holderAddress][medicineId];
            Batch storage batch = batches[holders[i].batchId]; // get and check that batch is active

            if (
                globalRegistry.verifyEntity(holderAddress)
                    && globalRegistry.getEntityRole(holderAddress) == IGlobalRegistry.Role.PHARMACY && medicineStock > 0
                    && batch.isActive
            ) {
                (string memory name, string memory location,,,,,) = globalRegistry.getEntityDetails(holderAddress);

                result[resultIndex] = PharmacyStock({
                    pharmacyAddress: holderAddress,
                    pharmacyName: name,
                    pharmacyLocation: location,
                    batchId: holders[i].batchId,
                    availableQuantity: medicineStock
                });

                resultIndex++;
            }
        }

        return result;
    }

    /**
     * @dev Get all holders of a specific medicine
     * @param medicineId ID of the medicine
     * @return MedicineHolder[] Array of MedicineHolder structs
     */
    function getMedicineHolders(string memory medicineId) public view returns (MedicineHolder[] memory) {
        return medicineHolders[medicineId];
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

    /**
     * @dev Get the number of medicines created
     * @return uint256 Number of medicines
     */
    function getMedicineCount() public view returns (uint256) {
        return medicineIds.length;
    }
    /**
     * @dev Get the number of batches created
     * @return uint256 Number of batches
     */

    function getBatchCount() public view returns (uint256) {
        return batchIds.length;
    }

    /**
     * @dev Deactivate a batch
     * @param batchId ID of the batch
     * @param medicineId ID of the medicine
     */
    function deactivateBatch(string memory batchId, string memory medicineId)
        public
        onlyManufacturer(medicineId)
        batchExists(batchId)
    {
        if (batches[batchId].isActive) {
            batches[batchId].isActive = false;
            emit BatchDeactivated(batchId, "Deactivated by Manufacturer");
        }
    }
    /**
     * @dev Deactivate expired batches
     * @dev It iterates through all batch IDs and checks if the current timestamp is greater than the expiry date.
     * This function is called by ChainLinks Automation to deactivate expired batches. Time-based trigger (24 hours) check.
     * @notice This function deactivates all expired batches in the registry.
     */

    function deactivateExpiredBatch() public {
        if (batchIds.length > 0) {
            for (uint256 i = 0; i < batchIds.length; i++) {
                string memory batchId = batchIds[i];
                Batch storage batch = batches[batchId];

                // Only check active batches
                if (batch.isActive) {
                    // Check if the batch has expired
                    if (block.timestamp > batch.expiryDate) {
                        // Deactivate expired batch
                        batch.isActive = false;
                        emit BatchDeactivated(batchId, "Expired");
                    }
                }
            }
        }
    }
    // =========================== HELPER FUNCTION ===========================

    function getEventType(IGlobalRegistry.Role role) internal pure returns (EventType) {
        EventType eventType;
        if (role == IGlobalRegistry.Role.MANUFACTURER) {
            eventType = DrugRegistry.EventType.MANUFACTURED;
        } else if (role == IGlobalRegistry.Role.SUPPLIER) {
            eventType = DrugRegistry.EventType.TO_SUPPLIER;
        } else if (role == IGlobalRegistry.Role.PHARMACY) {
            eventType = DrugRegistry.EventType.TO_PHARMACY;
        }

        return eventType;
    }
}
