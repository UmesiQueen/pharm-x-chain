// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGlobalRegistry} from "./GlobalRegistry.sol";
import {IDrugRegistry} from "./DrugRegistry.sol";

/**
 * @title SupplyChainRegistry
 * @author @UmesiQueen
 * @dev Manages supply chain tracking, inventory, and dispensing for medicines
 */
contract SupplyChainRegistry {
    // ================ ERRORS =================
    error SupplyChain__SenderIsNotAuthorized(address sender);
    error SupplyChain__ReceiverIsNotEligible(address receiver);
    error SupplyChain__BatchIsNotActive(string batchId);
    error SupplyChain__InvalidRegistryContractAddress(address registryAddress, string name);
    error SupplyChain__SenderHasInsufficientQuantity(uint256 requestedQuantity, uint256 availableQuantity);
    error SupplyChain__MinLengthRequired(string field, uint256 givenLength, uint256 minLength);

    // ================ STRUCTS ================
    struct MedicineHoldersStock {
        string batchId;
        address holderAddress;
        string holderName;
        string holderLocation;
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

    // Define a struct to hold both address and batchID
    struct MedicineHolder {
        address holderAddress;
        string batchId;
    }

    // ================ STATE VARIABLES ================
    IGlobalRegistry public globalRegistry;
    IDrugRegistry public drugRegistry;

    mapping(string => SupplyChainEvent[]) public supplyChainEvents;
    mapping(string => SupplyChainEvent[]) public batchEvents;
    mapping(address => mapping(string => uint256)) public inventory;
    mapping(string => MedicineHolder[]) public medicineHolders;

    // ================ EVENTS ================
    event MedicineTransferred(string indexed batchId, address indexed from, address indexed to, uint256 quantity);
    event MedicineDispensed(
        string indexed batchId, address indexed pharmacy, string indexed patientId, uint256 quantity
    );
    event LowInventoryAlert(address indexed medicineHolder, string indexed batchId, uint256 indexed quantity);
    event BatchInventoryInitialized(string medicineId, string batchId, address manufacturer, uint256 quantity);

    // ================ MODIFIERS ================
    modifier onlyRole(IGlobalRegistry.Role role) {
        if (!globalRegistry.verifyEntity(msg.sender) || globalRegistry.getEntityRole(msg.sender) != role) {
            revert SupplyChain__SenderIsNotAuthorized(msg.sender);
        }
        _;
    }

    modifier batchExists(string memory batchId) {
        drugRegistry.requireBatchExists(batchId);
        _;
    }

    modifier medicineExists(string memory medicineId) {
        drugRegistry.requireMedicineExists(medicineId);
        _;
    }

    constructor(address globalRegistryAddress, address drugRegistryAddress) {
        if (globalRegistryAddress == address(0)) {
            revert SupplyChain__InvalidRegistryContractAddress(globalRegistryAddress, "globalRegistry");
        }
        if (drugRegistryAddress == address(0)) {
            revert SupplyChain__InvalidRegistryContractAddress(drugRegistryAddress, "drugRegistry");
        }
        globalRegistry = IGlobalRegistry(globalRegistryAddress);
        drugRegistry = IDrugRegistry(drugRegistryAddress);
    }

    /**
     * @dev Initialize inventory for a new batch - called by DrugRegistry
     */
    function initializeBatchInventory(
        string memory medicineId,
        string memory batchId,
        address manufacturer,
        uint256 quantity
    ) external {
        // Only the drug registry contract can call this
        require(msg.sender == address(drugRegistry), "Only DrugRegistry can initialize batch inventory");

        // Add to manufacturer's inventory
        inventory[manufacturer][medicineId] += quantity;

        // Add manufacturer to medicine holders if this is their first stock
        if (inventory[manufacturer][medicineId] == quantity) {
            MedicineHolder memory newHolder = MedicineHolder({holderAddress: manufacturer, batchId: batchId});
            medicineHolders[medicineId].push(newHolder);
        }

        // Record supply chain event
        SupplyChainEvent memory newEvent = SupplyChainEvent({
            medicineId: medicineId,
            batchId: batchId,
            eventType: EventType.MANUFACTURED,
            fromEntity: address(0),
            toEntity: manufacturer,
            quantity: quantity,
            timestamp: block.timestamp,
            patientId: ""
        });

        supplyChainEvents[medicineId].push(newEvent);
        batchEvents[batchId].push(newEvent);

        emit BatchInventoryInitialized(medicineId, batchId, manufacturer, quantity);
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
            revert SupplyChain__SenderIsNotAuthorized(msg.sender);
        }

        // Get batch details from drug registry
        IDrugRegistry.Batch memory batch = drugRegistry.getBatchDetails(batchId);

        // Check if the batch is active
        if (!batch.isActive) {
            revert SupplyChain__BatchIsNotActive(batchId);
        }

        IGlobalRegistry.Role role;
        // verify receiver's address and role
        if (globalRegistry.verifyEntity(entityAddress)) {
            IGlobalRegistry.Role entityRole = globalRegistry.getEntityRole(entityAddress);

            // cannot make transfer to regulator
            if (entityRole != IGlobalRegistry.Role.REGULATOR) {
                role = entityRole;
            } else {
                revert SupplyChain__ReceiverIsNotEligible(entityAddress);
            }
        } else {
            revert SupplyChain__ReceiverIsNotEligible(entityAddress);
        }

        // Check if the quantity is valid
        if (quantity <= 0) {
            revert SupplyChain__MinLengthRequired("Medicine Quantity", quantity, 1);
        }

        // Check if the sender is the manufacturer, and if so, update the batch
        address manufacturer = drugRegistry.getMedicineManufacturer(batch.medicineId);
        if (manufacturer == msg.sender) {
            // Check if the batch has enough quantity
            if (batch.remainingQuantity < quantity) {
                revert SupplyChain__SenderHasInsufficientQuantity(quantity, batch.remainingQuantity);
            }
            // Update batch remaining quantity in DrugRegistry
            drugRegistry.updateBatchRemainingQuantity(batchId, batch.remainingQuantity - quantity);
        }

        // Check if the sender has enough quantity
        uint256 inventoryQuantity = inventory[msg.sender][batch.medicineId];
        if (inventoryQuantity < quantity) {
            revert SupplyChain__SenderHasInsufficientQuantity(quantity, inventoryQuantity);
        }

        // Update inventories
        inventory[msg.sender][batch.medicineId] -= quantity;
        inventory[entityAddress][batch.medicineId] += quantity;

        // emit low stock event if quantity is less than 10
        uint256 sendersInventory = inventory[msg.sender][batch.medicineId];
        if (sendersInventory <= 10) {
            emit LowInventoryAlert(msg.sender, batchId, sendersInventory);
        }

        // Add entity to medicine holders if this is their first stock
        if (inventory[entityAddress][batch.medicineId] == quantity) {
            MedicineHolder memory newHolder = MedicineHolder({holderAddress: entityAddress, batchId: batchId});
            medicineHolders[batch.medicineId].push(newHolder);
        }

        // get event type based on receiver's role
        EventType eventType = getEventType(role);

        // Record supply chain event
        SupplyChainEvent memory newEvent = SupplyChainEvent({
            medicineId: batch.medicineId,
            batchId: batchId,
            eventType: eventType,
            fromEntity: msg.sender,
            toEntity: entityAddress,
            quantity: quantity,
            timestamp: block.timestamp,
            patientId: ""
        });

        supplyChainEvents[batch.medicineId].push(newEvent);
        batchEvents[batchId].push(newEvent);

        emit MedicineTransferred(batchId, msg.sender, entityAddress, quantity);
    }

    /**
     * @dev Dispense medicine to a patient
     * @param batchId ID of the batch
     * @param quantity Quantity to dispense
     * @param patientId ID of the patient
     */
    function dispenseMedicine(string memory batchId, uint256 quantity, string memory patientId)
        public
        batchExists(batchId)
        onlyRole(IGlobalRegistry.Role.PHARMACY)
    {
        if (quantity <= 0) {
            revert SupplyChain__MinLengthRequired("Medicine Quantity", quantity, 1);
        }
        require(bytes(patientId).length > 0, "Patient ID cannot be empty");

        // Check if batch is active
        bool isActive = drugRegistry.isBatchActive(batchId);
        if (!isActive) {
            revert SupplyChain__BatchIsNotActive(batchId);
        }

        // Get medicineId from the batch
        IDrugRegistry.Batch memory batch = drugRegistry.getBatchDetails(batchId);

        // Check if the pharmacy has enough quantity
        uint256 inventoryQuantity = inventory[msg.sender][batch.medicineId];
        if (inventoryQuantity < quantity) {
            revert SupplyChain__SenderHasInsufficientQuantity(quantity, inventoryQuantity);
        }

        // Update inventories
        inventory[msg.sender][batch.medicineId] -= quantity;

        // emit low stock event if quantity is less than 10
        uint256 sendersInventory = inventory[msg.sender][batch.medicineId];
        if (sendersInventory <= 10) {
            emit LowInventoryAlert(msg.sender, batchId, sendersInventory);
        }

        // Record supply chain event
        SupplyChainEvent memory newEvent = SupplyChainEvent({
            medicineId: batch.medicineId,
            batchId: batchId,
            eventType: EventType.DISPENSED,
            fromEntity: msg.sender,
            toEntity: address(0),
            quantity: quantity,
            timestamp: block.timestamp,
            patientId: patientId
        });

        supplyChainEvents[batch.medicineId].push(newEvent);
        batchEvents[batchId].push(newEvent);

        emit MedicineDispensed(batchId, msg.sender, patientId, quantity);
    }

    // ================ GETTERS ================
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
     * @dev Get list of all medicine holders with available stock of a specific medicine
     * @param medicineId ID of the medicine
     * @return MedicineHoldersStock[] Array of MedicineHoldersStock structs
     */
    function getMedicineHoldersDetails(string calldata medicineId)
        public
        view
        medicineExists(medicineId)
        returns (MedicineHoldersStock[] memory)
    {
        MedicineHolder[] storage holders = medicineHolders[medicineId];
        uint256 holdersLength = holders.length;

        // First count valid pharmacies to size our array properly
        uint256 medicineHoldersCount = 0;
        for (uint256 i = 0; i < holdersLength; i++) {
            address holderAddress = holders[i].holderAddress;
            bool batchActive = drugRegistry.isBatchActive(holders[i].batchId);

            if (globalRegistry.verifyEntity(holderAddress) && inventory[holderAddress][medicineId] > 0 && batchActive) {
                medicineHoldersCount++;
            }
        }

        // If no pharmacies have stock, return early
        if (medicineHoldersCount == 0) {
            return new MedicineHoldersStock[](0);
        }

        MedicineHoldersStock[] memory result = new MedicineHoldersStock[](medicineHoldersCount);

        // Only if we have results to return, do the second loop
        uint256 resultIndex = 0;
        for (uint256 i = 0; i < holdersLength; i++) {
            address holderAddress = holders[i].holderAddress;
            uint256 availableMedicineStock = inventory[holderAddress][medicineId];
            bool batchActive = drugRegistry.isBatchActive(holders[i].batchId);

            if (globalRegistry.verifyEntity(holderAddress) && availableMedicineStock > 0 && batchActive) {
                (string memory name, string memory location,,,,,) = globalRegistry.getEntityDetails(holderAddress);

                result[resultIndex] = MedicineHoldersStock({
                    holderAddress: holderAddress,
                    holderName: name,
                    holderLocation: location,
                    batchId: holders[i].batchId,
                    availableQuantity: availableMedicineStock
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
     */
    function getSupplyChainHistory(string memory medicineId) public view returns (SupplyChainEvent[] memory) {
        return supplyChainEvents[medicineId];
    }

    /**
     * @dev Get supply chain events for a specific batch
     */
    function getBatchEvents(string memory batchId) public view returns (SupplyChainEvent[] memory) {
        return batchEvents[batchId];
    }

    /**
     * @dev Verify authenticity of a medicine
     * @param medicineId ID of the medicine
     * @return bool True if medicine is authentic
     */
    function verifyAuthenticity(string memory medicineId) public view returns (bool) {
        // Check that supply chain events exist
        if (supplyChainEvents[medicineId].length == 0) {
            return false;
        }

        // Check that the first event is MANUFACTURED
        if (supplyChainEvents[medicineId][0].eventType != EventType.MANUFACTURED) {
            return false;
        }

        // Check that the manufacturer in the event matches the registered manufacturer
        address manufacturer = drugRegistry.getMedicineManufacturer(medicineId);
        if (supplyChainEvents[medicineId][0].toEntity != manufacturer) {
            return false;
        }

        return true;
    }

    // =========================== HELPER FUNCTION ===========================
    function getEventType(IGlobalRegistry.Role role) internal pure returns (EventType) {
        EventType eventType;
        if (role == IGlobalRegistry.Role.MANUFACTURER) {
            eventType = EventType.MANUFACTURED;
        } else if (role == IGlobalRegistry.Role.SUPPLIER) {
            eventType = EventType.TO_SUPPLIER;
        } else if (role == IGlobalRegistry.Role.PHARMACY) {
            eventType = EventType.TO_PHARMACY;
        }

        return eventType;
    }
}
