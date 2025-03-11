# Decentralized Payments Gateway

![Decentralized Payments Gateway](https://github.com/Jay-shm/HACKINDIA2025-SPARK-3--BLOCK-CODERS/raw/master/Logo)

## 📜 Description
Have you heard of RazorPay?  Yes, a multibillion-dollar startup.  We acknowledge that it only allows debit cards, credit cards, and UPI, and the main worry is that it is CENTRALIZED (Shocked sounds playing).  This is why we decided to create something to express our love of cryptocurrency.

This is a truly decentralized payments interface that enables crypto payers to pay a merchant using a variety of EVM-based blockchains such as Base, Optimism, Ethereum mainnet, and others.  The program includes a payments page and a merchant dashboard that displays his/her earnings.  This application was created using Node.js, the Ethers library, and Solidity.  This application eliminates the hassle of verifying each transaction individually, displays a nice UI and gives retailers a more favorable attitude on cryptocurrency-based payment methods.

## 🚀 Installation

1. Clone the repository:
   ```sh
   git clone https://github.com/Jay-shm/HACKINDIA2025-SPARK-3--BLOCK-CODERS.git
   cd HACKINDIA2025-SPARK-3--BLOCK-CODERS
   ```

2. Install the dependencies:
   ```sh
   npm install
   ```
3. Setup Rainbow Toolkit:
   ```sh
   npm install @rainbow-me/rainbowkit wagmi viem@2.x @tanstack/react-query
   ```

## 🛠️ Running the Application

1. Launch the application:
   ```sh
   npm run dev
   ```

## 🧰 Technologies Used

- **Backend:**
  - Node.js
  - ethers library
  - Solidity

- **Frontend:**
  - TypeScript
  - Wallet Connect

## 🌟 Features

- Decentralized payments interface supporting multiple blockchains.
- Wallet to store received payments.
- Dashboard to display total earnings to the merchant.

## 📄 License

This project is licensed under the MIT License.

---

## 💡 Smart Contract Deployment

1. Visit [Remix IDE](https://remix.ethereum.org/)

2. Create new files and paste the smart contract code:
   - Create `PayMe3Core.sol` and paste the core contract code
   - Create `PayMe3Escrow.sol` and paste the escrow contract code
   - Create `TestToken.sol` and paste the test token contract code

3. Compile the contracts:
   - Select Solidity Compiler (0.8.0+) from the left sidebar
   - Make sure all required OpenZeppelin dependencies are imported correctly
   - Click "Compile" for each contract file
   - Verify there are no compilation errors

4. Deploy the contracts in order:
   - Switch to "Deploy & Run Transactions" in the left sidebar
   - Select "Injected Provider - MetaMask" as environment
   - Connect your MetaMask wallet
   - Deploy in this sequence:
     1. First deploy `TestToken.sol` (for testing purposes)
     2. Then deploy `PayMe3Core.sol`
     3. Finally deploy `PayMe3Escrow.sol` with the PayMe3Core address as constructor parameter

5. After deployment:
   - Copy and save each contract's deployed address
   - Save the ABIs from the "Compilation Details"
   - Update these addresses in your frontend configuration

## 📝 Testing the Contracts

1. In Remix IDE's "Deploy & Run Transactions" tab:
   - Each deployed contract will appear in the "Deployed Contracts" section
   - Expand each contract to see all available functions
   
2. Test Basic Functions:
   - Use the TestToken contract to mint some test tokens
   - Approve the PayMe3Core contract to spend tokens
   - Create a payment request using PayMe3Core
   - Test the escrow functionality using PayMe3Escrow

3. Important Notes:
   - Ensure your MetaMask is connected to the correct network
   - Keep track of transaction hashes for debugging
   - Monitor gas costs during testing