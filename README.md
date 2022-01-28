# Wiz

This is a proposal for how a Gnosis Safe module can be used to decentralize the DAO Treasury.

[Process Flow Diagram](docs/process/processflow.png)

Proposing a transaction for the treasury requires the transaction proposer to offer an amount of ETH as collateral to disincentivize an individual DAO member or group from performing an attack.

Whenever a transaction is proposed it is placed on a timelock for a predetermined amount of time that blocks all executions until the timelock has expired.

Any transactions under timelock can be contested by a quorom of dao members and marked as malicious.

If a quorom for marking the transaction as malicious is reached during the timelock period, the collateral is forwarded to the DAO treasury.

If a transaction is executed the collateral is returned to the transaction proposer.

---

### Note

There are two variables to be optimized:

- The minimum eth required for collateral
- The number of members needed to reach a malicious quorum
