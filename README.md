# 🚀 Stacks Smart Contracts

A comprehensive collection of production-ready Clarity smart contracts for the Stacks blockchain ecosystem. Built with security, modularity, and best practices in mind.

## 📦 Contracts

### 1. SIP-010 Fungible Token (`sip010-token.clar`)
A fully SIP-010 compliant fungible token with advanced features:
- **Minting & Burning** with role-based access control
- **Allowance system** (approve, transferFrom)
- **Pausable** functionality for emergency scenarios
- **Minter roles** for delegated minting
- Initial supply: 100M tokens, Max supply: 1B tokens

### 2. SIP-009 NFT Collection (`sip009-nft.clar`)
A complete NFT platform with built-in marketplace:
- **Full SIP-009 compliance** with metadata support
- **On-chain marketplace** with listing/buying/unlisting
- **Royalties** (5% on secondary sales)
- **Operator approvals** and single-token approvals
- Max supply: 10,000 NFTs, Mint price: 1 STX

### 3. DAO Governance (`dao-governance.clar`)
A decentralized governance system for community-driven decisions:
- **Proposal creation** with configurable voting periods
- **Weighted voting** based on member voting power
- **Quorum-based execution** (51% threshold)
- **Treasury management** for community funds
- **Vote delegation** support

### 4. DeFi Staking (`defi-staking.clar`)
A flexible staking protocol with time-locked rewards:
- **Multiple lock periods**: Flexible, 7-day, 30-day, 90-day
- **Reward multipliers**: Up to 2x for longer locks
- **Compound rewards** with per-block calculations
- **Emergency mode** for urgent unstaking
- **Staking history** tracking

### 5. Multi-Signature Wallet (`multisig-wallet.clar`)
A secure M-of-N multi-signature wallet:
- **Configurable confirmation threshold**
- **Transaction submission & confirmation** workflow
- **Transaction expiry** (7-day window)
- **Owner management** (add/remove)
- **Execution logging** for audit trails

## 🛠️ Prerequisites

- [Clarinet](https://github.com/stx-labs/clarinet) >= 2.0
- [Node.js](https://nodejs.org/) >= 18 (for testing)

## 🚀 Getting Started

```bash
# Clone the repository
git clone https://github.com/YOUR-USERNAME/stacks-smart-contracts.git
cd stacks-smart-contracts

# Check contracts
clarinet check

# Run tests
clarinet test

# Launch local devnet
clarinet devnet start

# Open Clarinet console
clarinet console
```

## 📁 Project Structure

```
stacks-smart-contracts/
├── Clarinet.toml              # Project configuration
├── contracts/
│   ├── sip010-token.clar      # Fungible token (SIP-010)
│   ├── sip009-nft.clar        # NFT collection (SIP-009)
│   ├── dao-governance.clar    # DAO governance system
│   ├── defi-staking.clar      # DeFi staking protocol
│   └── multisig-wallet.clar   # Multi-sig wallet
├── tests/                     # Contract tests
├── settings/
│   └── Devnet.toml            # Devnet configuration
└── README.md
```

## 🔒 Security

All contracts implement:
- **Access control** with owner/role checks
- **Input validation** on all public functions
- **Pausable patterns** for emergency stops
- **Overflow protection** via Clarity's built-in safety
- **Event logging** via `print` statements

## 🌐 Deployment

### Testnet Deployment
```bash
clarinet deployments generate --testnet
clarinet deployments apply -p deployments/default.testnet-plan.yaml
```

### Mainnet Deployment
```bash
clarinet deployments generate --mainnet
clarinet deployments apply -p deployments/default.mainnet-plan.yaml
```

## 📜 Standards

- **SIP-010**: Fungible Token Standard
- **SIP-009**: Non-Fungible Token Standard
- **Clarity**: Decidable smart contract language for Stacks

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Resources

- [Stacks Documentation](https://docs.stacks.co)
- [Clarity Language Reference](https://docs.stacks.co/clarity)
- [Clarinet Documentation](https://github.com/stx-labs/clarinet)
- [SIP-010 Standard](https://github.com/stacksgov/sips/blob/main/sips/sip-010/sip-010-fungible-token-standard.md)
- [SIP-009 Standard](https://github.com/stacksgov/sips/blob/main/sips/sip-009/sip-009-nft-standard.md)

---

Built with ❤️ for the Stacks ecosystem
