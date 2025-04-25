# Pharmaceutical Supply Chain Management System

A blockchain-based solution for transparent, secure tracking of pharmaceutical drugs throughout the supply chain.

## Overview

This system provides end-to-end tracking for medications from manufacturer to patient, ensuring authenticity and integrity throughout the pharmaceutical supply chain. The platform is designed to prevent counterfeiting, enable efficient recalls, and provide transparency to all stakeholders.

## Core Features

- **Entity Registration & Verification**: Secure registration and verification of all supply chain participants.
- **Medicine Registration & Approval**: Complete lifecycle management for drug registration and regulatory approval.
- **Batch Management**: Create, track, and manage medicine batches with expiration monitoring.
- **Supply Chain Tracking**: Transparent tracking of medicine transfers between manufacturers, suppliers, and pharmacies.
- **Patient Dispensing Records**: Secure recording of medicines dispensed to patients.
- **Authenticity Verification**: Verify the authenticity of medications through blockchain records.
- **Inventory Management**: Real-time inventory tracking across the supply chain with low stock alerts.

## Smart Contracts Architecture

### 1. GlobalRegistry.sol

The foundation of the system that manages participant registration and verification.

- Registers and verifies supply chain entities (Manufacturers, Suppliers, Pharmacies, Regulators)
- Maintains entity details including licensing and certification
- Provides role-based access control for the entire system

### 2. DrugRegistry.sol

Handles drug registration, approval, and batch management.

- Registers new medicines with detailed information
- Manages regulatory approval workflows
- Creates and tracks medicine batches with expiry date monitoring
- Automatically deactivates expired batches via Chainlink Automation

### 3. SupplyChainRegistry.sol

Tracks the movement of medicines through the supply chain.

- Records all medicine transfers between stakeholders
- Manages inventory across different entities
- Processes medicine dispensing to patients
- Provides comprehensive supply chain audit trail
- Verifies medicine authenticity

## Deployment Scripts

- **DeployGlobalRegistry.s.sol**: Deploys the GlobalRegistry contract and sets up the initial regulator.
- **DeployDrugRegistry.s.sol**: Deploys the DrugRegistry contract, connecting it to the GlobalRegistry.
- **DeploySupplyChainRegistry.s.sol**: Deploys the SupplyChainRegistry contract, connecting it to both the GlobalRegistry and DrugRegistry.

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/) and npm

### Installation

1. Clone the repository
   ```bash
   git clone https://github.com/UmesiQueen/pharm-x-chain.git
   cd pharm-x-chain
   ```

2. Install dependencies
   ```bash
   forge install
   ```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Coverage

```shell
$ forge coverage --no-match-coverage script
```

### Deployment

Deploy contracts in the following order:

1. GlobalRegistry
2. DrugRegistry
3. SupplyChainRegistry
   ```bash
   forge script <script path> --rpc-url <your-rpc-url> --private-key <your-private-key> --broadcast
   ```

## Role Descriptions

- **Regulator**: Government agencies or authorized regulatory bodies that approve medicines
- **Manufacturer**: Companies that produce pharmaceutical products
- **Supplier**: Wholesale distributors that purchase from manufacturers and sell to pharmacies
- **Pharmacy**: Retail pharmacies that dispense medicine to patients

## Security Features

- Role-based access control for all operations
- Supply chain event tracking for full auditability
- Verification mechanisms to ensure medicines are authentic
- Built-in expiration date enforcement
- Only approved medicines can enter the supply chain

## Acknowledgements

- [Foundry](https://github.com/foundry-rs/foundry)
- [Solidity](https://soliditylang.org/)
- [Cyfrin_Updraft](https://www.cyfrin.io/updraft)

---

Built with ❤️ by @UmesiQueen
