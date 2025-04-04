// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ================ INTERFACES ================

interface IGlobalRegistry {
    enum Role {
        NONE,
        MANUFACTURER,
        SUPPLIER,
        PHARMACY,
        REGULATOR
    }

    function verifyEntity(address entityAddress) external view returns (bool);

    function getEntityRole(address entityAddress) external view returns (Role);

    function getEntityDetails(address entityAddress)
        external
        view
        returns (
            string memory name,
            string memory location,
            string memory licenseNumber,
            Role role,
            bool isActive,
            uint256 registrationDate
        );

    function getManufacturerId(address manufacturerAddress) external view returns (string memory);
}

/**
 * @title GlobalRegistry
 * @author @UmesiQueen
 * @notice This contract manages the registration and verification of all supply chain participants
 * @dev Only the owner can register and deactivate entities
 * @dev Entities can be queried by any contract
 */
contract GlobalRegistry is IGlobalRegistry {
    // ================ ERRORS ================
    error GlobalRegistry__SenderIsNotOwner();
    error GlobalRegistry__EntityAlreadyRegistered(address entityAddress, IGlobalRegistry.Role role);
    error GlobalRegistry__EntityAlreadyDeactivated(address entityAddress, bool isActive);
    error GlobalRegistry__EntityAlreadyActivated(address entityAddress, bool isActive);
    error GlobalRegistry__EntityDoesNotExist();
    error GlobalRegistry__InvalidManufacturerAddress();
    // ================ STATE VARIABLES ================

    struct Entity {
        string name;
        string location;
        string licenseNumber;
        Role role;
        bool isActive;
        uint256 registrationDate;
    }

    address public owner;
    mapping(address => Entity) public entities;

    // ================ EVENTS ================
    event EntityRegistered(address indexed entityAddress, Role role, string name);
    event EntityDeactivated(address indexed entityAddress);
    event EntityActivated(address indexed entityAddress);

    // ================ MODIFIERS ================
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert GlobalRegistry__SenderIsNotOwner();
        }
        _;
    }

    constructor() {
        owner = msg.sender;
        // Register the deployer as a regulator
        entities[msg.sender] = Entity({
            name: "System Administrator",
            location: "N/A",
            licenseNumber: "ADMIN",
            role: Role.REGULATOR,
            isActive: true,
            registrationDate: block.timestamp
        });

        emit EntityRegistered(msg.sender, Role.REGULATOR, "System Administrator");
    }

    /**
     * @dev Register a new entity
     * @param entityAddress Address of the entity
     * @param role Role of the entity
     * @param name Name of the manufacturer
     * @param location Physical location of the manufacturer
     * @param license License number of the manufacturer
     */
    function registerEntity(
        address entityAddress,
        Role role,
        string memory name,
        string memory location,
        string memory license
    ) public onlyOwner {
        if (entities[entityAddress].role != Role.NONE) {
            revert GlobalRegistry__EntityAlreadyRegistered(entityAddress, entities[entityAddress].role);
        }

        entities[entityAddress] = Entity({
            name: name,
            location: location,
            licenseNumber: license,
            role: role,
            isActive: true,
            registrationDate: block.timestamp
        });

        emit EntityRegistered(entityAddress, role, name);
    }

    /**
     * @dev Verify if an entity is registered and active
     * @param entityAddress Address of the entity to verify
     * @return bool True if the entity is registered and active
     */
    function verifyEntity(address entityAddress) external view override returns (bool) {
        return entities[entityAddress].isActive;
    }

    /**
     * @dev Get the role of a registered entity
     * @param entityAddress Address of the entity
     * @return Role Role of the entity
     */
    function getEntityRole(address entityAddress) external view override returns (Role) {
        return entities[entityAddress].role;
    }

    /**
     * @dev Get the manufacturer ID of a registered manufacturer
     * @param manufacturerAddress Address of the manufacturer
     * @return uint256 Manufacturer ID
     */
    function getManufacturerId(address manufacturerAddress) external view override returns (string memory) {
        Entity storage entity = entities[manufacturerAddress];
        if (entity.role != Role.MANUFACTURER) {
            revert GlobalRegistry__InvalidManufacturerAddress();
        }

        return string(entity.licenseNumber);
    }

    /**
     * @dev Deactivate an entity
     * @param entityAddress Address of the entity to deactivate
     */
    function deactivateEntity(address entityAddress) public onlyOwner {
        require(entityAddress != address(0), "Invalid address");
        Entity storage entity = entities[entityAddress];

        if (entity.role == Role.NONE) {
            revert GlobalRegistry__EntityDoesNotExist();
        }
        if (!entity.isActive) {
            revert GlobalRegistry__EntityAlreadyDeactivated(entityAddress, entity.isActive);
        }

        entity.isActive = false;

        emit EntityDeactivated(entityAddress);
    }

    /**
     * @dev Activate an entity
     * @param entityAddress Address of the entity to activate
     */
    function activateEntity(address entityAddress) public onlyOwner {
        require(entityAddress != address(0), "Invalid address");
        Entity storage entity = entities[entityAddress];

        if (entity.role == Role.NONE) {
            revert GlobalRegistry__EntityDoesNotExist();
        }
        if (entity.isActive) {
            revert GlobalRegistry__EntityAlreadyActivated(entityAddress, entity.isActive);
        }

        entity.isActive = true;

        emit EntityActivated(entityAddress);
    }

    /**
     * @dev Get entity details
     * @param entityAddress Address of the entity
     * @return name Name of the entity
     * @return location Location of the entity
     * @return licenseNumber License number of the entity
     * @return role Role of the entity
     * @return isActive Active status of the entity
     * @return registrationDate Registration date of the entity
     */
    function getEntityDetails(address entityAddress)
        external
        view
        override
        returns (
            string memory name,
            string memory location,
            string memory licenseNumber,
            Role role,
            bool isActive,
            uint256 registrationDate
        )
    {
        if (entities[entityAddress].role == Role.NONE) {
            revert GlobalRegistry__EntityDoesNotExist();
        }

        Entity storage entity = entities[entityAddress];
        return
            (entity.name, entity.location, entity.licenseNumber, entity.role, entity.isActive, entity.registrationDate);
    }
}
