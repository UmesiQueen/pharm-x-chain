// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGlobalRegistry} from "./GlobalRegistry.sol";

interface IDrugRegistry {
    struct Batch {
        string batchId;
        string medicineId;
        uint256 quantity;
        uint256 remainingQuantity;
        uint256 productionDate;
        uint256 expiryDate;
        bool isActive;
    }

    function getMedicineDetailsById(string memory _medicineId)
        external
        view
        returns (
            string memory medicineId,
            string memory serialNo,
            string memory name,
            string memory brand,
            string memory ingredients,
            string memory details,
            uint256 registrationDate,
            address manufacturer,
            string memory manufacturerId,
            bool approved
        );
    function getBatchDetails(string memory _batchId) external view returns (Batch memory);
    function requireBatchExists(string memory batchId) external view;
    function requireMedicineExists(string memory medicineId) external view;
    function getMedicineManufacturer(string memory medicineId) external view returns (address);
    function updateBatchRemainingQuantity(string memory batchId, uint256 newRemainingQuantity) external;
    function isBatchActive(string memory batchId) external view returns (bool);
}

/**
 * @title DrugRegistry
 * @author @UmesiQueen
 * @dev Manages medicine information, registrations, and batch creation
 */
contract DrugRegistry is IDrugRegistry {
    // ================ ERRORS =================
    error DrugRegistry__SenderIsNotAuthorized(address sender);
    error DrugRegistry__MedicineExistenceStatus(string medicineId, bool exists);
    error DrugRegistry__BatchExistenceStatus(string batchId, bool exists);
    error DrugRegistry__InvalidRegistryContractAddress(address registryAddress);
    error DrugRegistry__MedicineApprovalStatus(string medicineId, bool approved);
    error DrugRegistry__MinLengthRequired(string field, uint256 givenLength, uint256 minLength);

    // ================ STRUCTS ================
    struct Medicine {
        string medicineId;
        string serialNo;
        string name;
        string brand;
        string ingredients;
        string details;
        uint256 registrationDate;
        address manufacturer;
        string manufacturerId;
        bool approved;
    }

    // ================ STATE VARIABLES ================
    IGlobalRegistry public globalRegistry;
    address public supplyChainRegistry;

    string[] public medicineIds;
    string[] public batchIds;

    mapping(string => Medicine) public medicines;
    mapping(string => Batch) public batches;
    mapping(string => string[]) public medicineBatches;

    // ================ EVENTS ================
    event MedicineRegistered(string indexed medicineId, string name, address manufacturer);
    event MedicineApproved(string indexed medicineId, address manufacturer);
    event BatchCreated(string indexed batchId, string medicineId, uint256 quantity);
    event BatchDeactivated(string indexed batchId, string reason);
    event SupplyChainRegistrySet(address indexed supplyChainRegistry);

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

    modifier onlySupplyChain() {
        require(msg.sender == supplyChainRegistry, "Only supply chain registry can call this function");
        _;
    }

    constructor(address globalRegistryAddress) {
        if (globalRegistryAddress == address(0)) {
            revert DrugRegistry__InvalidRegistryContractAddress(globalRegistryAddress);
        }
        globalRegistry = IGlobalRegistry(globalRegistryAddress);
    }

    /**
     * @dev Set the supply chain registry address
     * @param _supplyChainRegistry Address of the supply chain registry contract
     */
    function setSupplyChainRegistry(address _supplyChainRegistry) external onlyRole(IGlobalRegistry.Role.REGULATOR) {
        if (_supplyChainRegistry == address(0)) {
            revert DrugRegistry__InvalidRegistryContractAddress(_supplyChainRegistry);
        }

        supplyChainRegistry = _supplyChainRegistry;
        emit SupplyChainRegistrySet(_supplyChainRegistry);
    }

    /**
     * @dev Register a new medicine
     * @param medicineId ID of the medicine
     * @param serialNo Serial number of the medicine
     * @param name Name of the medicine
     * @param brand Brand of the medicine
     * @param ingredients Ingredients of the medicine
     * @param details Additional details about the medicine
     */
    function registerMedicine(
        string memory medicineId,
        string memory serialNo,
        string memory name,
        string memory brand,
        string memory ingredients,
        string memory details
    ) public onlyRole(IGlobalRegistry.Role.MANUFACTURER) {
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
        newMedicine.serialNo = serialNo;
        newMedicine.name = name;
        newMedicine.brand = brand;
        newMedicine.ingredients = ingredients;
        newMedicine.details = details;
        newMedicine.registrationDate = block.timestamp;
        newMedicine.manufacturer = msg.sender;
        newMedicine.manufacturerId = globalRegistry.getManufacturerId(msg.sender);
        newMedicine.approved = false;

        // Add to the list of registered medicines
        medicineIds.push(medicineId);

        emit MedicineRegistered(medicineId, name, msg.sender);
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
     */
    function createBatch(
        string memory medicineId,
        string memory batchId,
        uint256 quantity,
        uint256 productionDate,
        uint256 expiryDate
    ) public medicineExists(medicineId) onlyManufacturer(medicineId) {
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
        batchIds.push(batchId);

        emit BatchCreated(batchId, medicineId, quantity);

        // Now notify the SupplyChainRegistry of the new batch
        if (supplyChainRegistry != address(0)) {
            // Call the supply chain registry to initialize inventory for the manufacturer
            (bool success,) = supplyChainRegistry.call(
                abi.encodeWithSignature(
                    "initializeBatchInventory(string,string,address,uint256)", medicineId, batchId, msg.sender, quantity
                )
            );
            require(success, "Failed to initialize inventory in SupplyChainRegistry");
        }
    }

    /**
     * @dev Update batch remaining quantity - called only by SupplyChainRegistry
     */
    function updateBatchRemainingQuantity(string memory batchId, uint256 newRemainingQuantity)
        external
        override
        onlySupplyChain
        batchExists(batchId)
    {
        batches[batchId].remainingQuantity = newRemainingQuantity;
    }

    function verifyMedicine(string memory _medicineId) public view returns (bool) {
        return (bytes(medicines[_medicineId].medicineId).length != 0);
    }

    function requireMedicineExists(string memory medicineId) external view override {
        if (bytes(medicines[medicineId].medicineId).length == 0) {
            revert DrugRegistry__MedicineExistenceStatus(medicineId, false);
        }
    }

    function verifyBatch(string memory _batchId) public view returns (bool) {
        return (bytes(batches[_batchId].batchId).length != 0);
    }

    function requireBatchExists(string memory batchId) external view override {
        if (bytes(batches[batchId].batchId).length == 0) {
            revert DrugRegistry__BatchExistenceStatus(batchId, false);
        }
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

    // ================ GETTERS ================
    /**
     * @dev Get medicine details by ID
     * @param _medicineId ID of the medicine
     * @return medicineId ID of the medicine
     * @return serialNo Serial number of the medicine
     * @return name Name of the medicine
     * @return brand Brand of the medicine
     * @return ingredients Ingredients of the medicine
     * @return details Additional details about the medicine
     * @return registrationDate Registration date (Unix timestamp)
     * @return manufacturer Address of manufacturer
     * @return manufacturerId ID of the manufacturer
     * @return approved Approval status of the medicine
     */
    function getMedicineDetailsById(string memory _medicineId)
        external
        view
        medicineExists(_medicineId)
        returns (
            string memory medicineId,
            string memory serialNo,
            string memory name,
            string memory brand,
            string memory ingredients,
            string memory details,
            uint256 registrationDate,
            address manufacturer,
            string memory manufacturerId,
            bool approved
        )
    {
        Medicine storage medicine = medicines[_medicineId];

        return (
            medicine.medicineId,
            medicine.serialNo,
            medicine.name,
            medicine.brand,
            medicine.ingredients,
            medicine.details,
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
    function getBatchDetails(string memory batchId)
        external
        view
        override
        batchExists(batchId)
        returns (Batch memory)
    {
        return batches[batchId];
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

    function getMedicineIds() public view returns (string[] memory) {
        return medicineIds;
    }

    function getBatchIds() public view returns (string[] memory) {
        return batchIds;
    }

    /**
     * @dev Check if a batch is active
     */
    function isBatchActive(string memory batchId) external view override batchExists(batchId) returns (bool) {
        return batches[batchId].isActive;
    }

    /**
     * @dev Get medicine manufacturer address
     */
    function getMedicineManufacturer(string memory medicineId)
        public
        view
        medicineExists(medicineId)
        returns (address)
    {
        return medicines[medicineId].manufacturer;
    }
}
