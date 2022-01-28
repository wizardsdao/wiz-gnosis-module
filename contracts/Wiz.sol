// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.6;

import "@gnosis.pm/zodiac/contracts/core/Module.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IWETH} from "./IWETH.sol";

struct Tx {
    uint256 collateral;
    uint256 value;
    uint256 lockedUntil;
    uint256 id;
    address proposer;
    address to;
    Enum.Operation operation;
    bytes data;
}

abstract contract Wiz is Module, ReentrancyGuard {
    // gnosis safe address.
    address public safe;

    // erc721 nft smart contract to use for authentication purposes.
    IERC721 public nft;

    // The address of the WETH contract.
    address public weth;

    // txs are a public map of pending transactions.
    mapping(uint256 => Tx) public txs;

    // txId is a counter for keeping track of transactions.
    uint256 private txId = 1;

    mapping(uint256 => address[]) private txReporters;

    // marks are a public map of transaction invalidation requests.
    mapping(uint256 => uint256) public marks;

    // invalidationQuorum is the number of votes required to mark a transaction as invalid.
    uint256 invalidationQuorum;

    // the amount of collateral in wei that needs to be put up to propose a transaction. if the
    // transaction is marked as malicious then the collateral is lost.
    uint256 public collateralAmount;

    // collateralReceiver is the address that receives collateral of invalid transactions.
    address public collateralReceiver;

    // timelock is the amount of time required before a tx can be executed
    uint256 public timelock;

    event TxProposed(
        address indexed proposer,
        address indexed to,
        uint256 indexed id,
        uint256 lockedUntil,
        uint256 value,
        uint256 collateral,
        Enum.Operation operation,
        bytes data
    );

    event TxExecuted(uint256 indexed id);

    event TxInvalidated(uint256 indexed id);

    event TxFailed(uint256 indexed id);

    constructor(
        address _safe,
        IERC721 _nft,
        uint256 _quorum,
        uint256 _timelock
    ) {
        safe = _safe;
        nft = _nft;
        invalidationQuorum = _quorum;
        timelock = _timelock;
    }

    /// @dev proposes a transaction to be executed against the given gnosis safe.
    /// @param to Target of the transaction that should be executed
    /// @param value Wei value of the transaction that should be executed
    /// @param data Data of the transaction that should be executed
    /// @param operation Operation type of module transaction: 0 == call, 1 == delegate call
    function propose(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external payable nonReentrant {
        require(
            nft.balanceOf(msg.sender) > 0,
            "only dao members can execute transactions"
        );

        require(
            msg.value >= collateralAmount,
            "must send at least collateral amount"
        );

        Tx memory tran = Tx({
            id: txId,
            proposer: msg.sender,
            collateral: msg.value,
            lockedUntil: block.timestamp + timelock,
            to: to,
            value: value,
            data: data,
            operation: operation
        });

        txs[txId] = tran;
        txId++;

        emit TxProposed(
            tran.proposer,
            tran.to,
            txId,
            tran.lockedUntil,
            tran.value,
            tran.collateral,
            tran.operation,
            tran.data
        );
    }

    /// @dev executes a set of transactions for this given gnosis safe.
    /// @param id of the transaction that should be executed
    function execute(uint256 id) external nonReentrant returns (bool success) {
        Tx memory tran = txs[id];

        require(tran.id != 0, "transaction does not exist");

        require(
            nft.balanceOf(msg.sender) > 0,
            "only dao members can execute transactions"
        );

        require(
            tran.lockedUntil <= block.timestamp,
            "transaction is under timelock"
        );

        success = exec(tran.to, tran.value, tran.data, tran.operation);

        // send collateral back to proposer.
        _safeTransferETHWithFallback(tran.proposer, tran.collateral);
        delete txs[id];
        delete txReporters[id];

        if (!success) {
            emit TxFailed(id);
            return success;
        }

        emit TxExecuted(id);
        return success;
    }

    /// @dev invalidate allows a reporter to mark a transaction as malicious.
    /// @param id of the transaction that should be marked malicious.
    function invalidate(uint256 id) external nonReentrant {
        Tx memory tran = txs[id];

        require(tran.id != 0, "transaction does not exist");

        require(
            marks[id] < invalidationQuorum,
            "transaction has been invalidated"
        );

        // ensure that the reporter can only participate once for each transaction.
        for (uint256 i = 0; i < txReporters[tran.id].length; i++) {
            address addr = txReporters[tran.id][i];
            if (addr == msg.sender) {
                require(false, "sender has already reported this transaction");
            }
        }

        marks[id] = marks[id] + 1;
        txReporters[tran.id].push(msg.sender);

        if (marks[id] >= invalidationQuorum) {
            // send collateral to receiver since the transaction was deemed malicious.
            _safeTransferETHWithFallback(collateralReceiver, tran.collateral);

            emit TxInvalidated(id);
            delete txs[tran.id];
            delete txReporters[tran.id];
        }
    }

    /**
     * @notice Transfer ETH. If the ETH transfer fails, wrap the ETH and try send it as WETH.
     */
    function _safeTransferETHWithFallback(address to, uint256 amount) internal {
        if (!_safeTransferETH(to, amount)) {
            IWETH(weth).deposit{value: amount}();
            IERC20(weth).transfer(to, amount);
        }
    }

    /**
     * @notice Transfer ETH and return the success status.
     * @dev This function only forwards 30,000 gas to the callee.
     */
    function _safeTransferETH(address to, uint256 value)
        internal
        returns (bool)
    {
        (bool success, ) = to.call{value: value, gas: 30_000}(new bytes(0));
        return success;
    }
}
